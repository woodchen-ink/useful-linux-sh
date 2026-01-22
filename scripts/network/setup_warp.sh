#!/bin/bash

# Cloudflare WARP 管理脚本
# 版本: 1.0.0
# 功能: 安装、配置、管理 Cloudflare WARP

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

# WARP 配置
WARP_CONFIG_DIR="/etc/cloudflare-warp"
WARP_SOCKS_PORT=40000

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

# 检测系统类型
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        log_error "无法检测操作系统类型"
        exit 1
    fi
}

# 获取包管理器
get_package_manager() {
    if command -v apt &> /dev/null; then
        PKG_MANAGER="apt"
        PKG_UPDATE="apt update"
        PKG_INSTALL="apt install -y"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
        PKG_UPDATE="yum makecache"
        PKG_INSTALL="yum install -y"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        PKG_UPDATE="dnf makecache"
        PKG_INSTALL="dnf install -y"
    else
        log_error "未找到支持的包管理器"
        exit 1
    fi
}

# 检查 WARP 是否已安装
check_warp_installed() {
    if command -v warp-cli &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# 安装依赖
install_dependencies() {
    log_info "正在安装必要的依赖..."

    $PKG_UPDATE

    if [ "$PKG_MANAGER" = "apt" ]; then
        $PKG_INSTALL curl wget gnupg lsb-release apt-transport-https ca-certificates
    elif [ "$PKG_MANAGER" = "yum" ] || [ "$PKG_MANAGER" = "dnf" ]; then
        $PKG_INSTALL curl wget gnupg2 ca-certificates
    fi

    log_success "依赖安装完成"
}

# 安装 WARP
install_warp() {
    log_info "开始安装 Cloudflare WARP..."

    if check_warp_installed; then
        log_warn "WARP 已经安装"
        return 0
    fi

    # 安装依赖
    install_dependencies

    # 根据不同系统安装 WARP
    if [ "$PKG_MANAGER" = "apt" ]; then
        log_info "在 Debian/Ubuntu 系统上安装 WARP..."

        # 添加 Cloudflare GPG 密钥
        curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg

        # 添加 WARP 软件源
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list

        # 更新并安装
        apt update
        apt install -y cloudflare-warp

    elif [ "$PKG_MANAGER" = "yum" ] || [ "$PKG_MANAGER" = "dnf" ]; then
        log_info "在 CentOS/RHEL 系统上安装 WARP..."

        # 添加 WARP 软件源
        curl -fsSL https://pkg.cloudflareclient.com/cloudflare-warp-ascii.repo | tee /etc/yum.repos.d/cloudflare-warp.repo

        # 安装
        $PKG_INSTALL cloudflare-warp
    fi

    if check_warp_installed; then
        log_success "WARP 安装成功"

        # 注册 WARP
        log_info "正在注册 WARP..."
        warp-cli registration new

        # 启用 WARP
        systemctl enable --now warp-svc

        return 0
    else
        log_error "WARP 安装失败"
        return 1
    fi
}

# 配置 SOCKS5 代理
setup_socks_proxy() {
    if ! check_warp_installed; then
        log_error "WARP 未安装,请先安装 WARP"
        return 1
    fi

    log_info "正在配置 SOCKS5 代理..."

    # 读取用户输入端口
    read -p "请输入 SOCKS5 代理端口 (默认: 40000): " custom_port
    WARP_SOCKS_PORT=${custom_port:-40000}

    # 设置代理模式
    warp-cli mode proxy

    # 设置代理端口
    warp-cli proxy port $WARP_SOCKS_PORT

    # 连接 WARP
    warp-cli connect

    sleep 3

    # 检查连接状态
    if warp-cli status | grep -q "Connected"; then
        log_success "SOCKS5 代理配置成功"
        log_info "代理地址: socks5://127.0.0.1:$WARP_SOCKS_PORT"
    else
        log_error "SOCKS5 代理配置失败"
        return 1
    fi
}

# 查看 WARP 状态
show_status() {
    if ! check_warp_installed; then
        log_error "WARP 未安装"
        return 1
    fi

    echo -e "\n${CYAN}=== Cloudflare WARP 状态 ===${NC}\n"

    # WARP 连接状态
    echo -e "${BOLD}连接状态:${NC}"
    warp-cli status
    echo ""

    # WARP 设置
    echo -e "${BOLD}当前设置:${NC}"
    warp-cli settings
    echo ""

    # 账户信息
    echo -e "${BOLD}账户信息:${NC}"
    warp-cli account
    echo ""

    # 服务状态
    echo -e "${BOLD}服务状态:${NC}"
    systemctl status warp-svc --no-pager
    echo ""
}

# 更换账号
change_account() {
    if ! check_warp_installed; then
        log_error "WARP 未安装"
        return 1
    fi

    log_warn "更换账号将删除当前账号信息"
    read -p "确认要更换账号吗? (y/n): " confirm

    if [ "$confirm" != "y" ]; then
        log_info "操作已取消"
        return 0
    fi

    # 断开连接
    warp-cli disconnect

    # 删除当前注册
    warp-cli registration delete

    # 重新注册
    log_info "正在注册新账号..."
    warp-cli registration new

    # 重新连接
    warp-cli connect

    log_success "账号更换成功"

    # 显示新账号信息
    warp-cli account
}

# 更换 IP
change_ip() {
    if ! check_warp_installed; then
        log_error "WARP 未安装"
        return 1
    fi

    log_info "正在更换 IP..."

    # 断开连接
    warp-cli disconnect

    sleep 2

    # 重新连接
    warp-cli connect

    sleep 3

    # 检查状态
    if warp-cli status | grep -q "Connected"; then
        log_success "IP 更换成功"

        # 显示新 IP (如果可用)
        log_info "正在检查新 IP..."
        if command -v curl &> /dev/null; then
            new_ip=$(curl -s --socks5 127.0.0.1:$WARP_SOCKS_PORT https://api.ip.sb/ip 2>/dev/null)
            if [ -n "$new_ip" ]; then
                log_info "当前 IP: $new_ip"
            fi
        fi
    else
        log_error "IP 更换失败"
        return 1
    fi
}

# 启用 WARP
enable_warp() {
    if ! check_warp_installed; then
        log_error "WARP 未安装"
        return 1
    fi

    log_info "正在启用 WARP..."

    systemctl enable --now warp-svc
    warp-cli connect

    sleep 3

    if warp-cli status | grep -q "Connected"; then
        log_success "WARP 已启用"
    else
        log_error "WARP 启用失败"
        return 1
    fi
}

# 禁用 WARP
disable_warp() {
    if ! check_warp_installed; then
        log_error "WARP 未安装"
        return 1
    fi

    log_info "正在禁用 WARP..."

    warp-cli disconnect
    systemctl disable --now warp-svc

    log_success "WARP 已禁用"
}

# 卸载 WARP
uninstall_warp() {
    if ! check_warp_installed; then
        log_warn "WARP 未安装"
        return 0
    fi

    log_warn "此操作将完全卸载 WARP"
    read -p "确认要卸载吗? (y/n): " confirm

    if [ "$confirm" != "y" ]; then
        log_info "操作已取消"
        return 0
    fi

    log_info "正在卸载 WARP..."

    # 断开连接
    warp-cli disconnect

    # 删除注册
    warp-cli registration delete

    # 停止服务
    systemctl stop warp-svc
    systemctl disable warp-svc

    # 卸载软件包
    if [ "$PKG_MANAGER" = "apt" ]; then
        apt remove -y cloudflare-warp
        apt autoremove -y
        rm -f /etc/apt/sources.list.d/cloudflare-client.list
        rm -f /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    elif [ "$PKG_MANAGER" = "yum" ] || [ "$PKG_MANAGER" = "dnf" ]; then
        $PKG_MANAGER remove -y cloudflare-warp
        rm -f /etc/yum.repos.d/cloudflare-warp.repo
    fi

    # 清理配置文件
    rm -rf /var/lib/cloudflare-warp
    rm -rf /etc/cloudflare-warp

    log_success "WARP 卸载完成"
}

# 测试连接
test_connection() {
    if ! check_warp_installed; then
        log_error "WARP 未安装"
        return 1
    fi

    log_info "正在测试 WARP 连接..."

    # 检查 WARP 状态
    if ! warp-cli status | grep -q "Connected"; then
        log_error "WARP 未连接"
        return 1
    fi

    # 测试直连
    log_info "测试直连 IP:"
    direct_ip=$(curl -s https://api.ip.sb/ip 2>/dev/null)
    echo -e "  直连 IP: ${GREEN}$direct_ip${NC}"

    # 测试 WARP IP
    if command -v curl &> /dev/null; then
        log_info "测试 WARP IP:"
        warp_ip=$(curl -s --socks5 127.0.0.1:$WARP_SOCKS_PORT https://api.ip.sb/ip 2>/dev/null)
        if [ -n "$warp_ip" ]; then
            echo -e "  WARP IP: ${GREEN}$warp_ip${NC}"

            # 测试延迟
            log_info "测试延迟:"
            start_time=$(date +%s%N)
            curl -s --socks5 127.0.0.1:$WARP_SOCKS_PORT https://www.cloudflare.com > /dev/null 2>&1
            end_time=$(date +%s%N)
            latency=$(( (end_time - start_time) / 1000000 ))
            echo -e "  延迟: ${GREEN}${latency}ms${NC}"

            log_success "连接测试完成"
        else
            log_error "无法通过 WARP 获取 IP"
            return 1
        fi
    else
        log_warn "curl 未安装,跳过 IP 测试"
    fi
}

# 显示帮助信息
show_help() {
    echo -e "${CYAN}=== Cloudflare WARP 管理脚本 ===${NC}\n"
    echo -e "${BOLD}使用方法:${NC}"
    echo -e "  $0 [选项]\n"
    echo -e "${BOLD}选项:${NC}"
    echo -e "  install      - 安装 WARP"
    echo -e "  uninstall    - 卸载 WARP"
    echo -e "  status       - 查看状态"
    echo -e "  enable       - 启用 WARP"
    echo -e "  disable      - 禁用 WARP"
    echo -e "  proxy        - 配置 SOCKS5 代理"
    echo -e "  account      - 更换账号"
    echo -e "  changeip     - 更换 IP"
    echo -e "  test         - 测试连接"
    echo -e "  help         - 显示帮助\n"
}

# 主菜单
show_menu() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║   Cloudflare WARP 管理工具           ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}\n"

    if check_warp_installed; then
        echo -e "${GREEN}[状态] WARP 已安装${NC}\n"
    else
        echo -e "${RED}[状态] WARP 未安装${NC}\n"
    fi

    echo -e "${BOLD}请选择操作:${NC}"
    echo -e "  ${GREEN}1.${NC} 安装 WARP"
    echo -e "  ${GREEN}2.${NC} 配置 SOCKS5 代理"
    echo -e "  ${GREEN}3.${NC} 查看状态"
    echo -e "  ${GREEN}4.${NC} 启用 WARP"
    echo -e "  ${GREEN}5.${NC} 禁用 WARP"
    echo -e "  ${GREEN}6.${NC} 更换账号"
    echo -e "  ${GREEN}7.${NC} 更换 IP"
    echo -e "  ${GREEN}8.${NC} 测试连接"
    echo -e "  ${GREEN}9.${NC} 卸载 WARP"
    echo -e "  ${RED}0.${NC} 退出"
    echo ""
}

# 主函数
main() {
    check_root
    detect_os
    get_package_manager

    # 如果有命令行参数,直接执行对应命令
    if [ $# -gt 0 ]; then
        case "$1" in
            install)
                install_warp
                ;;
            uninstall)
                uninstall_warp
                ;;
            status)
                show_status
                ;;
            enable)
                enable_warp
                ;;
            disable)
                disable_warp
                ;;
            proxy)
                setup_socks_proxy
                ;;
            account)
                change_account
                ;;
            changeip)
                change_ip
                ;;
            test)
                test_connection
                ;;
            help|--help|-h)
                show_help
                ;;
            *)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
        exit 0
    fi

    # 交互式菜单
    while true; do
        show_menu
        read -p "请输入选项 [0-9]: " choice

        case $choice in
            1)
                install_warp
                ;;
            2)
                setup_socks_proxy
                ;;
            3)
                show_status
                ;;
            4)
                enable_warp
                ;;
            5)
                disable_warp
                ;;
            6)
                change_account
                ;;
            7)
                change_ip
                ;;
            8)
                test_connection
                ;;
            9)
                uninstall_warp
                ;;
            0)
                log_info "退出脚本"
                exit 0
                ;;
            *)
                log_error "无效的选项"
                ;;
        esac

        echo ""
        read -p "按回车键继续..."
    done
}

# 执行主函数
main "$@"
