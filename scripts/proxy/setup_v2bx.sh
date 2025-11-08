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
    echo -e "  /etc/V2bX/config.yml"
    echo
    echo -e "${YELLOW}📚 相关文档:${NC}"
    echo -e "  项目主页: https://github.com/wyx2685/V2bX"
    echo -e "  配置文档: https://github.com/wyx2685/V2bX/wiki"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo
}

# 主函数
main() {
    # 检查权限
    check_root

    # 检查依赖
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
        exit 0
    fi
}

# 运行主函数
main "$@"
