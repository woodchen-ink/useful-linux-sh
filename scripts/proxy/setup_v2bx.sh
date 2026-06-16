#!/bin/bash

# V2bX 安装管理脚本
# 版本: 1.0
# 功能: 调用上游官方脚本进行 V2bX 管理 (自动同步上游更新)
# 项目: https://github.com/wyx2685/V2bX
# 上游脚本: https://github.com/wyx2685/V2bX-script

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 上游官方脚本地址
UPSTREAM_SCRIPT_URL="https://raw.githubusercontent.com/wyx2685/V2bX-script/master/install.sh"

# V2bX 安装产物路径 (与上游官方脚本一致)
SERVICE_NAME="V2bX"
SYSTEMD_UNIT="/etc/systemd/system/V2bX.service"   # systemd 服务单元
ALPINE_INITD="/etc/init.d/V2bX"                   # Alpine OpenRC 服务脚本
INSTALL_DIR="/usr/local/V2bX"                     # 二进制及核心文件目录
CONFIG_DIR="/etc/V2bX"                            # 配置目录 (config.json/证书/路由等)
MGR_CMD="/usr/bin/V2bX"                           # 管理命令主脚本
MGR_CMD_LINK="/usr/bin/v2bx"                      # 管理命令小写软链

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        log_info "请使用: sudo $0"
        exit 1
    fi
}

# 检查依赖
check_dependencies() {
    local missing_deps=()

    # 检查wget或curl
    if ! command -v wget &> /dev/null && ! command -v curl &> /dev/null; then
        missing_deps+=("wget 或 curl")
    fi

    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "缺少必要的依赖工具: ${missing_deps[*]}"
        log_info "请先安装缺失的工具"
        log_info "Ubuntu/Debian: apt update && apt install wget curl -y"
        log_info "CentOS/RHEL: yum install wget curl -y"
        exit 1
    fi
}

# 判断当前系统使用的服务管理器: systemd / openrc(alpine) / none
detect_init_system() {
    if command -v systemctl &> /dev/null && [ -d /run/systemd/system ]; then
        echo "systemd"
    elif command -v rc-update &> /dev/null; then
        echo "openrc"
    else
        echo "none"
    fi
}

# 检测 V2bX 各组件安装状态
# 副作用: 设置以下全局变量供卸载与展示使用
#   HAS_SYSTEMD_UNIT / HAS_ALPINE_INITD / HAS_INSTALL_DIR / HAS_CONFIG_DIR
#   HAS_MGR_CMD / HAS_MGR_LINK / IS_RUNNING / V2BX_INSTALLED
detect_install() {
    HAS_SYSTEMD_UNIT=false
    HAS_ALPINE_INITD=false
    HAS_INSTALL_DIR=false
    HAS_CONFIG_DIR=false
    HAS_MGR_CMD=false
    HAS_MGR_LINK=false
    IS_RUNNING=false

    [ -f "$SYSTEMD_UNIT" ] && HAS_SYSTEMD_UNIT=true
    [ -f "$ALPINE_INITD" ] && HAS_ALPINE_INITD=true
    [ -d "$INSTALL_DIR" ] && HAS_INSTALL_DIR=true
    [ -d "$CONFIG_DIR" ] && HAS_CONFIG_DIR=true
    [ -f "$MGR_CMD" ] && HAS_MGR_CMD=true
    # -L 单独判断: 软链指向已被删除时 -f 为假但 -L 仍为真, 需识别为残留
    if [ -L "$MGR_CMD_LINK" ] || [ -e "$MGR_CMD_LINK" ]; then
        HAS_MGR_LINK=true
    fi

    # 进程是否在运行: 优先服务管理器, 再兜底进程匹配 (覆盖手动启动/脱离 systemd 的情况)
    local init_sys
    init_sys=$(detect_init_system)
    if [ "$init_sys" = "systemd" ] && systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        IS_RUNNING=true
    elif [ "$init_sys" = "openrc" ] && rc-service "$SERVICE_NAME" status &> /dev/null; then
        IS_RUNNING=true
    elif pgrep -x V2bX &> /dev/null; then
        IS_RUNNING=true
    fi

    # 任一组件存在即视为已安装
    if $HAS_SYSTEMD_UNIT || $HAS_ALPINE_INITD || $HAS_INSTALL_DIR || \
       $HAS_CONFIG_DIR || $HAS_MGR_CMD || $HAS_MGR_LINK || $IS_RUNNING; then
        V2BX_INSTALLED=true
    else
        V2BX_INSTALLED=false
    fi
}

# 展示检测到的安装组件清单
show_detected() {
    detect_install

    echo -e "${YELLOW}🔍 检测到的 V2bX 安装状态:${NC}"
    echo

    if [ "$V2BX_INSTALLED" = false ]; then
        log_warn "未检测到 V2bX 的任何安装痕迹"
        return 1
    fi

    if $IS_RUNNING; then
        echo -e "  运行状态:   ${GREEN}运行中${NC}"
    else
        echo -e "  运行状态:   ${YELLOW}未运行${NC}"
    fi

    local mark_yes="${GREEN}✔ 已安装${NC}"
    local mark_no="${YELLOW}— 未发现${NC}"

    $HAS_SYSTEMD_UNIT && echo -e "  服务单元:   $mark_yes  $SYSTEMD_UNIT" || true
    $HAS_ALPINE_INITD && echo -e "  服务脚本:   $mark_yes  $ALPINE_INITD" || true
    if $HAS_INSTALL_DIR; then
        echo -e "  程序目录:   $mark_yes  $INSTALL_DIR"
    else
        echo -e "  程序目录:   $mark_no  $INSTALL_DIR"
    fi
    if $HAS_CONFIG_DIR; then
        echo -e "  配置目录:   $mark_yes  $CONFIG_DIR  ${RED}(含配置/证书, 删除不可恢复)${NC}"
    else
        echo -e "  配置目录:   $mark_no  $CONFIG_DIR"
    fi
    if $HAS_MGR_CMD; then
        echo -e "  管理命令:   $mark_yes  $MGR_CMD"
    else
        echo -e "  管理命令:   $mark_no  $MGR_CMD"
    fi
    $HAS_MGR_LINK && echo -e "  命令软链:   $mark_yes  $MGR_CMD_LINK" || true

    echo
    return 0
}

# 停止 V2bX 进程并关闭开机自启
stop_v2bx_service() {
    local init_sys
    init_sys=$(detect_init_system)

    if [ "$init_sys" = "systemd" ]; then
        if $HAS_SYSTEMD_UNIT; then
            log_info "停止并禁用 systemd 服务: $SERVICE_NAME"
            systemctl stop "$SERVICE_NAME" 2>/dev/null
            systemctl disable "$SERVICE_NAME" 2>/dev/null
        fi
    elif [ "$init_sys" = "openrc" ]; then
        if $HAS_ALPINE_INITD; then
            log_info "停止并移除 OpenRC 服务: $SERVICE_NAME"
            rc-service "$SERVICE_NAME" stop 2>/dev/null
            rc-update del "$SERVICE_NAME" 2>/dev/null
        fi
    fi

    # 兜底: 服务管理器没接管或仍有残留进程时, 直接杀掉
    if pgrep -x V2bX &> /dev/null; then
        log_warn "检测到残留 V2bX 进程, 正在强制结束..."
        pkill -x V2bX 2>/dev/null
        sleep 1
        pgrep -x V2bX &> /dev/null && pkill -9 -x V2bX 2>/dev/null
    fi
}

# 卸载 V2bX: 检测 -> 确认 -> 停进程 -> 删文件
uninstall_v2bx() {
    echo
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}🗑️  V2bX 卸载${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo

    if ! show_detected; then
        log_info "无需卸载"
        return 0
    fi

    echo -e "${RED}⚠️  卸载将停止 V2bX 进程并删除上述所有已安装的文件与目录${NC}"
    echo -e "${RED}   配置目录 $CONFIG_DIR 内的配置和证书将一并删除, 不可恢复${NC}"
    echo
    read -p "确认卸载 V2bX? (yes/N): " confirm
    if [[ ! $confirm == "yes" ]]; then
        log_info "已取消卸载 (需输入 yes 确认)"
        return 0
    fi

    echo
    log_info "开始卸载 V2bX..."

    # 1. 停止进程 + 关闭自启
    stop_v2bx_service

    # 2. 删除服务定义并刷新服务管理器
    local init_sys
    init_sys=$(detect_init_system)
    if $HAS_SYSTEMD_UNIT; then
        rm -f "$SYSTEMD_UNIT"
        log_info "已删除服务单元: $SYSTEMD_UNIT"
    fi
    if $HAS_ALPINE_INITD; then
        rm -f "$ALPINE_INITD"
        log_info "已删除服务脚本: $ALPINE_INITD"
    fi
    if [ "$init_sys" = "systemd" ]; then
        systemctl daemon-reload 2>/dev/null
        systemctl reset-failed 2>/dev/null
    fi

    # 3. 删除程序目录与配置目录
    if $HAS_INSTALL_DIR; then
        rm -rf "$INSTALL_DIR"
        log_info "已删除程序目录: $INSTALL_DIR"
    fi
    if $HAS_CONFIG_DIR; then
        rm -rf "$CONFIG_DIR"
        log_info "已删除配置目录: $CONFIG_DIR"
    fi

    # 4. 删除管理命令及软链
    if $HAS_MGR_CMD; then
        rm -f "$MGR_CMD"
        log_info "已删除管理命令: $MGR_CMD"
    fi
    if $HAS_MGR_LINK; then
        rm -f "$MGR_CMD_LINK"
        log_info "已删除命令软链: $MGR_CMD_LINK"
    fi

    echo
    # 复检: 确认无残留
    detect_install
    if [ "$V2BX_INSTALLED" = false ]; then
        log_success "V2bX 已完全卸载"
    else
        log_warn "卸载完成, 但仍检测到残留, 请手动检查:"
        show_detected
    fi
    echo
}

# 显示脚本信息
show_info() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}              V2bX 安装管理脚本 (ULS集成版)            ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${YELLOW}📋 关于 V2bX:${NC}"
    echo -e "  • 基于多核心的 V2board 节点服务端"
    echo -e "  • 支持协议: Vmess/Vless, Trojan, Shadowsocks, Hysteria"
    echo -e "  • 支持自动申请和续签 TLS 证书"
    echo -e "  • 支持多节点管理和跨节点 IP 限制"
    echo -e "  • 项目地址: ${BLUE}https://github.com/wyx2685/V2bX${NC}"
    echo
    echo -e "${YELLOW}⚠️  注意事项:${NC}"
    echo -e "  • 本脚本会自动调用上游官方安装脚本"
    echo -e "  • 自动同步上游所有更新和功能"
    echo -e "  • 需要配合修改版 V2board 使用"
    echo -e "  • 建议在干净的系统上安装"
    echo -e "  • 安装前请确保服务器时间正确"
    echo
}

# 下载并执行上游官方脚本
run_upstream_script() {
    local temp_script="/tmp/v2bx_upstream_install.sh"

    log_info "正在从上游下载最新的官方安装脚本..."
    log_info "脚本地址: $UPSTREAM_SCRIPT_URL"
    echo

    # 尝试使用wget下载
    if command -v wget &> /dev/null; then
        if wget -N "$UPSTREAM_SCRIPT_URL" -O "$temp_script" 2>&1; then
            log_success "脚本下载成功 (使用 wget)"
        else
            log_error "wget 下载失败,尝试使用 curl..."
            if command -v curl &> /dev/null; then
                if curl -fsSL "$UPSTREAM_SCRIPT_URL" -o "$temp_script"; then
                    log_success "脚本下载成功 (使用 curl)"
                else
                    log_error "下载失败"
                    log_info "请检查网络连接,或手动执行:"
                    echo "wget -N $UPSTREAM_SCRIPT_URL && bash install.sh"
                    return 1
                fi
            else
                log_error "下载工具不可用"
                return 1
            fi
        fi
    elif command -v curl &> /dev/null; then
        if curl -fsSL "$UPSTREAM_SCRIPT_URL" -o "$temp_script"; then
            log_success "脚本下载成功 (使用 curl)"
        else
            log_error "下载失败"
            log_info "请检查网络连接,或手动执行:"
            echo "curl -fsSL $UPSTREAM_SCRIPT_URL | bash"
            return 1
        fi
    fi

    # 检查下载的文件是否有效
    if [ ! -f "$temp_script" ] || [ ! -s "$temp_script" ]; then
        log_error "下载的脚本文件无效或为空"
        rm -f "$temp_script"
        return 1
    fi

    # 给予执行权限
    chmod +x "$temp_script"

    # 执行上游脚本
    log_info "正在执行上游官方安装脚本..."
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo

    bash "$temp_script"
    local exit_code=$?

    echo
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"

    # 清理临时文件
    rm -f "$temp_script"

    if [ $exit_code -eq 0 ]; then
        log_success "上游脚本执行完成"
    else
        log_warn "上游脚本执行完成 (退出码: $exit_code)"
    fi

    return $exit_code
}

# 显示快捷命令提示
show_quick_commands() {
    echo
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}💡 V2bX 常用管理命令:${NC}"
    echo
    echo -e "  ${GREEN}systemctl start V2bX${NC}     - 启动服务"
    echo -e "  ${GREEN}systemctl stop V2bX${NC}      - 停止服务"
    echo -e "  ${GREEN}systemctl restart V2bX${NC}   - 重启服务"
    echo -e "  ${GREEN}systemctl status V2bX${NC}    - 查看状态"
    echo -e "  ${GREEN}journalctl -u V2bX -f${NC}    - 查看实时日志"
    echo
    echo -e "${YELLOW}📝 配置文件位置:${NC}"
    echo -e "  /etc/V2bX/config.json"
    echo
    echo -e "${YELLOW}🗑️  卸载:${NC} 重新运行本脚本选择 \"卸载\", 或执行 ${GREEN}$0 --uninstall${NC}"
    echo
    echo -e "${YELLOW}📚 相关文档:${NC}"
    echo -e "  项目主页: https://github.com/wyx2685/V2bX"
    echo -e "  配置文档: https://github.com/wyx2685/V2bX/wiki"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo
}

# 安装 / 管理 V2bX (调用上游官方脚本)
do_install() {
    check_dependencies

    # 显示信息
    show_info

    # 询问用户是否继续
    echo -e "${YELLOW}准备执行上游官方安装脚本${NC}"
    read -p "是否继续? (Y/n): " continue_choice

    if [[ ! $continue_choice =~ ^[Nn] ]]; then
        # 运行上游脚本
        run_upstream_script

        # 显示快捷命令
        show_quick_commands
    else
        log_info "已取消操作"
        return 0
    fi
}

# 主菜单 (无参直接进入)
show_main_menu() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}              V2bX 安装管理脚本 (ULS集成版)            ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo

    # 探测并提示当前安装状态
    detect_install
    if [ "$V2BX_INSTALLED" = true ]; then
        if $IS_RUNNING; then
            echo -e "  当前状态: ${GREEN}已安装 · 运行中${NC}"
        else
            echo -e "  当前状态: ${YELLOW}已安装 · 未运行${NC}"
        fi
    else
        echo -e "  当前状态: ${YELLOW}未安装${NC}"
    fi
    echo

    echo -e "${YELLOW}请选择操作:${NC}"
    echo "1) 安装 / 管理 V2bX   (调用上游官方脚本: 安装/升级/配置等)"
    echo "2) 卸载 V2bX          (停止进程并删除服务/程序/配置文件)"
    echo "3) 查看安装状态       (检测已安装的组件与运行状态)"
    echo "0) 退出"
    echo
    read -p "请选择 (0-3) [默认: 1]: " action_choice
    action_choice=${action_choice:-1}

    case $action_choice in
        1) do_install ;;
        2) uninstall_v2bx ;;
        3) show_detected ;;
        0)
            log_info "已退出"
            exit 0
            ;;
        *)
            log_error "无效选择"
            exit 1
            ;;
    esac
}

# 主函数
main() {
    check_root

    # 参数直达, 跳过菜单 (供 ULS 或自动化调用)
    case "$1" in
        --uninstall)
            uninstall_v2bx
            exit 0
            ;;
        --install)
            do_install
            exit 0
            ;;
        --status)
            show_detected
            exit 0
            ;;
    esac

    show_main_menu
}

# 信号处理
trap 'log_error "脚本被中断"; exit 1' INT TERM

# 运行主函数
main "$@"
