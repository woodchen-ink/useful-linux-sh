#!/bin/bash

# ULS - Useful Linux Scripts 统一管理脚本
# 版本: 1.5.1
# 作者: woodchen-ink

# 配置信息
SCRIPT_VERSION="1.5.1"
SCRIPT_NAME="uls.sh"
SCRIPT_URL="https://raw.githubusercontent.com/woodchen-ink/useful-linux-sh/refs/heads/main"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/uls"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

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

# 创建必要的目录
setup_directories() {
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$CONFIG_DIR/scripts"
    mkdir -p "$CONFIG_DIR/backup"
}

# 下载脚本函数
download_script() {
    local script_name="$1"
    local script_path="$2"
    local local_path="$CONFIG_DIR/scripts/$script_name"

    log_info "正在下载 $script_name..."

    if curl -fsSL "$SCRIPT_URL/$script_path" -o "$local_path"; then
        chmod +x "$local_path"
        log_success "$script_name 下载完成"
        return 0
    else
        log_error "$script_name 下载失败"
        return 1
    fi
}

# 执行脚本函数 - 每次都重新下载最新版本
run_script() {
    local script_name="$1"
    local local_path="$CONFIG_DIR/scripts/$script_name"

    # 每次都重新下载最新版本
    log_info "正在下载最新版本的 $script_name..."
    rm -f "$local_path"  # 删除旧版本

    case $script_name in
        "add-swap.sh")
            download_script "$script_name" "scripts/system/add-swap.sh" || return 1
            ;;
        "enable_bbr.sh")
            download_script "$script_name" "scripts/system/enable_bbr.sh" || return 1
            ;;
        "setup_ufw.sh")
            download_script "$script_name" "scripts/security/setup_ufw.sh" || return 1
            ;;
        "setup_fail2ban.sh")
            download_script "$script_name" "scripts/security/setup_fail2ban.sh" || return 1
            ;;
        "setup_dns.sh")
            download_script "$script_name" "scripts/network/setup_dns.sh" || return 1
            ;;
        "migrate_volumes.sh")
            download_script "$script_name" "scripts/docker/migrate_volumes.sh" || return 1
            ;;
        "setup_v2bx.sh")
            download_script "$script_name" "scripts/proxy/setup_v2bx.sh" || return 1
            ;;
        "server_benchmark.sh")
            download_script "$script_name" "scripts/benchmark/server_benchmark.sh" || return 1
            ;;
        "security_monitor.sh")
            download_script "$script_name" "scripts/security/security_monitor.sh" || return 1
            ;;
        "port_forward.sh")
            download_script "$script_name" "scripts/network/port_forward.sh" || return 1
            ;;
        "ipv6_manager.sh")
            download_script "$script_name" "scripts/network/ipv6_manager.sh" || return 1
            ;;
        "setup_gost.sh")
            download_script "$script_name" "scripts/network/setup_gost.sh" || return 1
            ;;
        "setup_warp.sh")
            download_script "$script_name" "scripts/network/setup_warp.sh" || return 1
            ;;
        *)
            log_error "未知脚本: $script_name"
            return 1
            ;;
    esac

    # 执行脚本
    log_info "正在执行 $script_name..."
    bash "$local_path"
}

# 显示主菜单
show_menu() {
    # 只有在交互式终端时才清屏
    if [ -t 0 ]; then
        clear
    fi
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}                    ULS - Useful Linux Scripts                   ${CYAN}║${NC}"
    echo -e "${CYAN}║${WHITE}                       常用Linux脚本工具箱                        ${CYAN}║${NC}"
    echo -e "${CYAN}║${WHITE}                          版本: $SCRIPT_VERSION                           ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${YELLOW}📋 请选择要执行的操作:${NC}"
    echo
    echo -e "${WHITE}  ${BLUE}1.${NC} ${GREEN}🔄 Swap空间管理${NC}     - 一键添加swap空间"
    echo -e "${WHITE}  ${BLUE}2.${NC} ${GREEN}🚀 BBR TCP优化${NC}      - 启用BBR拥塞控制算法"
    echo -e "${WHITE}  ${BLUE}3.${NC} ${GREEN}🛡️  UFW防火墙配置${NC}   - 配置UFW防火墙规则"
    echo -e "${WHITE}  ${BLUE}4.${NC} ${GREEN}🚫 Fail2ban防护${NC}     - 安装配置入侵防护"
    echo -e "${WHITE}  ${BLUE}5.${NC} ${GREEN}🔍 安全监控管理${NC}     - UFW和Fail2ban监控管理"
    echo -e "${WHITE}  ${BLUE}6.${NC} ${GREEN}🌐 DNS配置锁定${NC}      - 设置并锁定DNS服务器"
    echo -e "${WHITE}  ${BLUE}7.${NC} ${GREEN}🔀 端口转发管理${NC}     - 配置防火墙端口转发规则"
    echo -e "${WHITE}  ${BLUE}8.${NC} ${GREEN}🌍 IPv6管理工具${NC}     - IPv4优先级/禁用IPv6"
    echo -e "${WHITE}  ${BLUE}9.${NC} ${GREEN}🔌 GOST代理管理${NC}     - HTTP/SOCKS5代理服务"
    echo -e "${WHITE}  ${BLUE}10.${NC} ${GREEN}☁️  WARP代理管理${NC}     - Cloudflare WARP代理"
    echo -e "${WHITE}  ${BLUE}11.${NC} ${GREEN}🐳 Docker Volumes迁移${NC} - 跨服务器迁移Docker卷"
    echo -e "${WHITE}  ${BLUE}12.${NC} ${GREEN}🚄 V2bX节点管理${NC}     - V2board节点服务端管理"
    echo -e "${WHITE}  ${BLUE}13.${NC} ${GREEN}📊 服务器性能测试${NC}   - 综合性能和网络测试"
    echo
    echo -e "${WHITE}  ${PURPLE}14.${NC} ${CYAN}🔄 更新ULS脚本${NC}      - 更新本管理脚本"
    echo -e "${WHITE}  ${PURPLE}15.${NC} ${CYAN}🗑️  卸载ULS脚本${NC}     - 卸载并清理所有文件"
    echo
    echo -e "${WHITE}  ${RED}0.${NC} ${RED}❌ 退出程序${NC}"
    echo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
}

# 版本比对函数 - 支持语义化版本
# 返回: 0 表示 $1 < $2, 1 表示 $1 >= $2
version_lt() {
    local ver1=$1
    local ver2=$2

    # 移除可能的 'v' 前缀
    ver1=${ver1#v}
    ver2=${ver2#v}

    # 使用sort -V进行版本比对
    if [ "$ver1" = "$ver2" ]; then
        return 1  # 版本相同
    fi

    # sort -V 会按语义化版本排序,第一个就是较小的版本
    local sorted_first=$(printf '%s\n%s' "$ver1" "$ver2" | sort -V | head -n1)

    if [ "$sorted_first" = "$ver1" ]; then
        return 0  # ver1 < ver2
    else
        return 1  # ver1 >= ver2
    fi
}

# 清理旧备份文件 - 保留最近3个版本
clean_old_backups() {
    if [ -d "$CONFIG_DIR/backup" ]; then
        local backup_count=$(ls -1 "$CONFIG_DIR/backup"/uls_*.sh 2>/dev/null | wc -l)

        if [ $backup_count -gt 3 ]; then
            log_info "清理旧备份文件 (保留最近3个版本)..."
            # 按时间排序,删除最旧的备份文件
            ls -t "$CONFIG_DIR/backup"/uls_*.sh 2>/dev/null | tail -n +4 | while read -r old_backup; do
                rm -f "$old_backup"
                log_info "已删除旧备份: $(basename "$old_backup")"
            done
        fi
    fi
}

# 清理缓存脚本
clean_cache() {
    if [ -d "$CONFIG_DIR/scripts" ]; then
        local script_count=$(ls -1 "$CONFIG_DIR/scripts"/*.sh 2>/dev/null | wc -l)
        if [ $script_count -gt 0 ]; then
            log_info "发现 $script_count 个缓存脚本"
            read -p "是否清理缓存脚本? (y/N): " clean_choice

            if [[ $clean_choice =~ ^[Yy] ]]; then
                rm -f "$CONFIG_DIR/scripts"/*.sh
                log_success "缓存已清理"
            else
                log_info "保留缓存文件"
            fi
        else
            log_info "没有缓存文件需要清理"
        fi
    else
        log_info "缓存目录不存在"
    fi
}

# 获取GitHub最新Release版本
get_latest_release() {
    local api_url="https://api.github.com/repos/woodchen-ink/useful-linux-sh/releases/latest"
    local latest_version

    # 尝试从GitHub API获取最新版本
    if command -v jq >/dev/null 2>&1; then
        latest_version=$(curl -s "$api_url" | jq -r '.tag_name' 2>/dev/null)
    else
        # 如果没有jq，使用grep解析
        latest_version=$(curl -s "$api_url" | grep '"tag_name":' | head -n1 | cut -d'"' -f4)
    fi

    # 如果API失败，回退到直接检查脚本文件
    if [ -z "$latest_version" ] || [ "$latest_version" = "null" ]; then
        log_warn "无法从GitHub API获取版本信息，检查脚本文件..."
        local temp_file="/tmp/uls_check.sh"
        if curl -fsSL "$SCRIPT_URL/uls.sh" -o "$temp_file" 2>/dev/null; then
            latest_version=$(grep 'SCRIPT_VERSION=' "$temp_file" | head -n1 | cut -d'"' -f2)
            rm -f "$temp_file"
        fi
    fi

    # 移除可能的 v 前缀，统一返回纯数字版本号
    latest_version=${latest_version#v}
    echo "$latest_version"
}

# 更新ULS脚本
update_uls() {
    log_info "正在检查ULS脚本更新..."

    local latest_version=$(get_latest_release)
    local temp_file="/tmp/uls_new.sh"

    if [ -z "$latest_version" ]; then
        log_error "无法获取最新版本信息"
        return 1
    fi

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}当前版本:${NC} ${BOLD}v$SCRIPT_VERSION${NC}"
    echo -e "${GREEN}最新版本:${NC} ${BOLD}v$latest_version${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # 使用语义化版本比对
    if version_lt "$SCRIPT_VERSION" "$latest_version"; then
        echo ""
        log_info "🎉 发现新版本可用!"
        echo ""

        # 询问是否更新
        read -p "是否立即更新? (Y/n): " update_choice
        update_choice=${update_choice:-Y}  # 默认为Y

        if [[ ! $update_choice =~ ^[Yy] ]]; then
            log_info "已取消更新"
            return 0
        fi

        echo ""
        log_info "正在下载新版本..."

        # 从GitHub Release下载，如果失败则从主分支下载
        local download_success=false
        local release_url="https://github.com/woodchen-ink/useful-linux-sh/releases/download/$latest_version/uls.sh"

        if curl -fsSL "$release_url" -o "$temp_file" 2>/dev/null; then
            download_success=true
            log_info "✓ 从Release下载成功"
        elif curl -fsSL "$SCRIPT_URL/uls.sh" -o "$temp_file" 2>/dev/null; then
            download_success=true
            log_info "✓ 从主分支下载成功"
        fi

        if [ "$download_success" = true ] && [ -f "$temp_file" ]; then
            # 验证下载的文件
            if bash -n "$temp_file" 2>/dev/null; then
                # 备份当前版本
                mkdir -p "$CONFIG_DIR/backup"
                local backup_file="$CONFIG_DIR/backup/uls_${SCRIPT_VERSION}_$(date +%Y%m%d_%H%M%S).sh"
                cp "$0" "$backup_file"
                log_info "✓ 已备份当前版本到: $backup_file"

                # 更新脚本
                cp "$temp_file" "$0"
                chmod +x "$0"

                # 如果安装到系统目录，也更新那里的副本
                if [ -f "$INSTALL_DIR/uls" ]; then
                    cp "$temp_file" "$INSTALL_DIR/uls"
                    chmod +x "$INSTALL_DIR/uls"
                    log_info "✓ 已更新系统命令"
                fi

                rm -f "$temp_file"

                # 清理旧备份
                clean_old_backups

                echo ""
                log_success "🎊 ULS脚本已成功更新到版本 v$latest_version"
                echo ""
                log_info "重新启动脚本中..."
                sleep 2
                exec "$0"
            else
                log_error "下载的文件语法检查失败"
                rm -f "$temp_file"
                return 1
            fi
        else
            log_error "下载更新文件失败"
            return 1
        fi
    else
        echo ""
        log_success "✓ 当前已是最新版本"
        echo ""
    fi
}

# 安装ULS到系统
install_uls() {
    log_info "将ULS安装到系统路径..."

    if cp "$0" "$INSTALL_DIR/uls"; then
        chmod +x "$INSTALL_DIR/uls"
        log_success "ULS已安装到 $INSTALL_DIR/uls"
        log_info "现在可以在任何地方使用 'sudo uls' 命令"
    else
        log_error "安装失败"
    fi
}

# 卸载ULS脚本
uninstall_uls() {
    echo -e "${RED}⚠️  警告: 即将卸载ULS脚本和所有相关文件${NC}"
    echo -e "${YELLOW}这将删除以下内容:${NC}"
    echo -e "  • $CONFIG_DIR/ (配置和脚本目录)"
    echo -e "  • $INSTALL_DIR/uls (系统命令)"
    echo -e "  • 所有下载的脚本文件"
    echo

    read -p "是否确认卸载? (输入 'yes' 确认): " confirm

    if [ "$confirm" = "yes" ]; then
        log_info "正在卸载ULS..."

        # 删除配置目录
        if [ -d "$CONFIG_DIR" ]; then
            rm -rf "$CONFIG_DIR"
            log_info "已删除配置目录: $CONFIG_DIR"
        fi

        # 删除系统命令
        if [ -f "$INSTALL_DIR/uls" ]; then
            rm -f "$INSTALL_DIR/uls"
            log_info "已删除系统命令: $INSTALL_DIR/uls"
        fi

        log_success "ULS脚本已完全卸载"
        log_info "感谢使用ULS工具箱！"

        exit 0
    else
        log_info "取消卸载操作"
    fi
}

# 显示脚本信息
show_info() {
    echo -e "${CYAN}📋 ULS脚本信息:${NC}"
    echo -e "版本: $SCRIPT_VERSION"
    echo -e "配置目录: $CONFIG_DIR"
    echo -e "脚本目录: $CONFIG_DIR/scripts"
    echo -e "备份目录: $CONFIG_DIR/backup"

    if [ -d "$CONFIG_DIR/scripts" ]; then
        local script_count=$(ls -1 "$CONFIG_DIR/scripts"/*.sh 2>/dev/null | wc -l)
        echo -e "已下载脚本: $script_count 个"
    fi

    echo
}

# 主程序循环
main_loop() {
    while true; do
        show_menu

        read -p "请输入选项 (0-14): " choice

        case $choice in
            1)
                echo
                run_script "add-swap.sh"
                ;;
            2)
                echo
                run_script "enable_bbr.sh"
                ;;
            3)
                echo
                run_script "setup_ufw.sh"
                ;;
            4)
                echo
                run_script "setup_fail2ban.sh"
                ;;
            5)
                echo
                run_script "security_monitor.sh"
                ;;
            6)
                echo
                run_script "setup_dns.sh"
                ;;
            7)
                echo
                run_script "port_forward.sh"
                ;;
            8)
                echo
                run_script "ipv6_manager.sh"
                ;;
            9)
                echo
                run_script "setup_gost.sh"
                ;;
            10)
                echo
                run_script "setup_warp.sh"
                ;;
            11)
                echo
                run_script "migrate_volumes.sh"
                ;;
            12)
                echo
                run_script "setup_v2bx.sh"
                ;;
            13)
                echo
                run_script "server_benchmark.sh"
                ;;
            14)
                echo
                update_uls
                ;;
            15)
                echo
                uninstall_uls
                ;;
            0)
                echo
                log_info "感谢使用ULS工具箱！"
                exit 0
                ;;
            *)
                echo
                log_error "无效选项，请重新选择"
                ;;
        esac

        if [ $choice -ne 0 ]; then
            echo
            echo -e "${CYAN}按任意键继续...${NC}"
            read -n 1
        fi
    done
}

# 初始化函数
initialize() {
    # 检查curl是否安装
    if ! command -v curl &> /dev/null; then
        log_error "curl 未安装，请先安装curl"
        log_info "Ubuntu/Debian: sudo apt update && sudo apt install curl"
        log_info "CentOS/RHEL: sudo yum install curl"
        exit 1
    fi

    # 设置目录
    setup_directories

    # 如果是首次运行，询问是否安装到系统
    if [ ! -f "$INSTALL_DIR/uls" ] && [ "$0" != "$INSTALL_DIR/uls" ]; then
        echo -e "${YELLOW}是否将ULS安装到系统路径？${NC}"
        echo -e "安装后可在任何地方使用 'sudo uls' 命令"
        read -p "安装? (y/N): " install_choice

        if [[ $install_choice =~ ^[Yy] ]]; then
            install_uls
            echo
        fi
    fi
}

# 主函数
main() {
    # 检查参数
    case "$1" in
        "--version"|"-v")
            echo "ULS (Useful Linux Scripts) v$SCRIPT_VERSION"
            exit 0
            ;;
        "--help"|"-h")
            echo "ULS - Useful Linux Scripts 工具箱"
            echo ""
            echo "用法: $0 [选项]"
            echo ""
            echo "选项:"
            echo "  -v, --version    显示版本信息"
            echo "  -h, --help       显示帮助信息"
            echo "  --info           显示脚本信息"
            echo ""
            exit 0
            ;;
        "--info")
            show_info
            exit 0
            ;;
    esac

    # 检测是否通过管道运行
    if [ ! -t 0 ]; then
        echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║  检测到通过管道运行,ULS需要交互式终端才能正常使用   ║${NC}"
        echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
        echo
        echo -e "${GREEN}请使用以下命令下载并运行:${NC}"
        echo
        echo -e "${CYAN}# 使用短链接:${NC}"
        echo -e "curl -fsSL https://l.czl.net/q/uls -o uls.sh && chmod +x uls.sh && sudo ./uls.sh"
        echo
        echo -e "${CYAN}# 或使用完整链接:${NC}"
        echo -e "curl -fsSL https://raw.githubusercontent.com/woodchen-ink/useful-linux-sh/refs/heads/main/uls.sh -o uls.sh && chmod +x uls.sh && sudo ./uls.sh"
        echo
        exit 1
    fi

    # 检查权限
    check_root

    # 初始化
    initialize

    # 启动主循环
    main_loop
}

# 信号处理
trap 'echo -e "\n${YELLOW}程序被中断${NC}"; exit 1' INT TERM

# 运行主函数
main "$@"