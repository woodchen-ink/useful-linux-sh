#!/bin/bash

# DNS设置脚本 - 设置DNS为8.8.8.8和1.1.1.1，并防止更改

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# DNS服务器配置
PRIMARY_DNS="8.8.8.8"
SECONDARY_DNS="1.1.1.1"
PRIMARY_DNS_V6="2001:4860:4860::8888"
SECONDARY_DNS_V6="2606:4700:4700::1111"

# 是否支持IPv6
HAS_IPV6=false

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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        log_info "请使用: sudo $0"
        exit 1
    fi
}

# 检测操作系统
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        log_error "无法检测操作系统"
        exit 1
    fi

    log_info "检测到操作系统: $OS $VERSION"
}

# 检测IPv6支持
detect_ipv6() {
    log_step "检测IPv6支持..."

    # 检查是否有IPv6地址(排除本地链路地址)
    if ip -6 addr show scope global 2>/dev/null | grep -q "inet6"; then
        HAS_IPV6=true
        log_info "检测到IPv6支持已启用"

        # 显示IPv6地址
        local ipv6_addr=$(ip -6 addr show scope global | grep inet6 | head -1 | awk '{print $2}' | cut -d'/' -f1)
        if [ -n "$ipv6_addr" ]; then
            log_info "IPv6地址: $ipv6_addr"
        fi
    else
        HAS_IPV6=false
        log_warn "未检测到IPv6支持，将仅配置IPv4 DNS"
    fi
}

# 备份原始配置
backup_config() {
    log_step "备份原始DNS配置..."

    # 备份 /etc/resolv.conf
    if [ -f /etc/resolv.conf ]; then
        cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%Y%m%d_%H%M%S)
        log_info "已备份 /etc/resolv.conf"
    fi

    # 备份 NetworkManager 配置（如果存在）
    if [ -d /etc/NetworkManager ]; then
        if [ -f /etc/NetworkManager/NetworkManager.conf ]; then
            cp /etc/NetworkManager/NetworkManager.conf /etc/NetworkManager/NetworkManager.conf.backup.$(date +%Y%m%d_%H%M%S)
            log_info "已备份 NetworkManager 配置"
        fi
    fi
}

# 配置DNS服务（更安全的方式）
configure_dns_services() {
    log_step "配置DNS相关服务..."

    # 检查并处理 systemd-resolved
    if systemctl is-active --quiet systemd-resolved; then
        log_info "检测到 systemd-resolved 正在运行"
        log_warn "是否要停用 systemd-resolved？这可能影响某些系统功能"
        echo -e "${YELLOW}选项:${NC}"
        echo "1) 保持 systemd-resolved 运行，通过配置文件设置DNS"
        echo "2) 停用 systemd-resolved，直接控制 /etc/resolv.conf"
        echo "3) 跳过，仅设置静态DNS"

        read -p "请选择 (1-3) [默认: 1]: " choice
        choice=${choice:-1}

        case $choice in
            1)
                log_info "配置 systemd-resolved 使用指定DNS..."
                mkdir -p /etc/systemd/resolved.conf.d

                # 构建DNS列表
                local dns_list="$PRIMARY_DNS $SECONDARY_DNS"
                if [ "$HAS_IPV6" = "true" ]; then
                    dns_list="$dns_list $PRIMARY_DNS_V6 $SECONDARY_DNS_V6"
                fi

                cat > /etc/systemd/resolved.conf.d/dns.conf << RESOLV_EOF
[Resolve]
DNS=$dns_list
FallbackDNS=
DNSSEC=yes
DNSOverTLS=opportunistic
Cache=yes
DNSStubListener=yes
RESOLV_EOF
                systemctl restart systemd-resolved
                # 确保 /etc/resolv.conf 指向 systemd-resolved
                if [ ! -L /etc/resolv.conf ] || [ "$(readlink /etc/resolv.conf)" != "../run/systemd/resolve/stub-resolv.conf" ]; then
                    ln -sf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
                fi
                SYSTEMD_RESOLVED_MODE=true
                ;;
            2)
                log_info "停用 systemd-resolved..."
                systemctl stop systemd-resolved
                systemctl disable systemd-resolved
                SYSTEMD_RESOLVED_MODE=false
                ;;
            3)
                log_info "跳过 systemd-resolved 配置"
                SYSTEMD_RESOLVED_MODE=false
                ;;
        esac
    else
        SYSTEMD_RESOLVED_MODE=false
    fi

    # 处理 NetworkManager
    if systemctl is-active --quiet NetworkManager; then
        log_info "配置 NetworkManager DNS设置..."

        # 创建NetworkManager配置，但不完全禁用DNS管理
        mkdir -p /etc/NetworkManager/conf.d
        cat > /etc/NetworkManager/conf.d/dns.conf << EOF
[main]
dns=default
EOF

        # 重启NetworkManager使配置生效
        systemctl reload NetworkManager
        log_info "已配置 NetworkManager"
    fi
}

# 设置DNS
configure_dns() {
    log_step "配置DNS服务器..."

    if [ "$SYSTEMD_RESOLVED_MODE" = "true" ]; then
        log_info "DNS通过 systemd-resolved 配置完成"
        log_info "  IPv4 主DNS: $PRIMARY_DNS (Google DNS)"
        log_info "  IPv4 备DNS: $SECONDARY_DNS (Cloudflare DNS)"
        if [ "$HAS_IPV6" = "true" ]; then
            log_info "  IPv6 主DNS: $PRIMARY_DNS_V6 (Google DNS)"
            log_info "  IPv6 备DNS: $SECONDARY_DNS_V6 (Cloudflare DNS)"
        fi
    else
        # 创建新的 resolv.conf
        cat > /etc/resolv.conf << RESOLV_CONF_EOF
# DNS配置 - 由setup_dns.sh脚本生成
# 请勿手动修改此文件
nameserver $PRIMARY_DNS
nameserver $SECONDARY_DNS
RESOLV_CONF_EOF

        # 如果支持IPv6,添加IPv6 DNS
        if [ "$HAS_IPV6" = "true" ]; then
            cat >> /etc/resolv.conf << RESOLV_CONF_V6_EOF
nameserver $PRIMARY_DNS_V6
nameserver $SECONDARY_DNS_V6
RESOLV_CONF_V6_EOF
        fi

        # 添加选项配置
        cat >> /etc/resolv.conf << RESOLV_CONF_OPT_EOF

# 选项配置
options timeout:2
options attempts:3
options rotate
options single-request-reopen
RESOLV_CONF_OPT_EOF

        log_info "DNS服务器已设置为:"
        log_info "  IPv4 主DNS: $PRIMARY_DNS (Google DNS)"
        log_info "  IPv4 备DNS: $SECONDARY_DNS (Cloudflare DNS)"
        if [ "$HAS_IPV6" = "true" ]; then
            log_info "  IPv6 主DNS: $PRIMARY_DNS_V6 (Google DNS)"
            log_info "  IPv6 备DNS: $SECONDARY_DNS_V6 (Cloudflare DNS)"
        fi
    fi
}

# 锁定DNS配置防止更改
lock_dns_config() {
    log_step "锁定DNS配置防止更改..."

    if [ "$SYSTEMD_RESOLVED_MODE" = "true" ]; then
        log_info "systemd-resolved 模式下，DNS配置已通过系统服务锁定"
        # 锁定 systemd-resolved 配置文件
        if [ -f /etc/systemd/resolved.conf.d/dns.conf ]; then
            chattr +i /etc/systemd/resolved.conf.d/dns.conf 2>/dev/null || {
                log_warn "无法锁定 systemd-resolved 配置文件"
            }
        fi
    else
        # 设置 resolv.conf 为不可更改
        chattr +i /etc/resolv.conf 2>/dev/null || {
            log_warn "无法使用chattr锁定文件，尝试其他方法..."
        }
    fi

    # 创建保护脚本
    cat > /usr/local/bin/protect-dns.sh << 'PROTECT_SCRIPT_EOF'
#!/bin/bash
# DNS保护脚本
PRIMARY_DNS="8.8.8.8"
SECONDARY_DNS="1.1.1.1"
PRIMARY_DNS_V6="2001:4860:4860::8888"
SECONDARY_DNS_V6="2606:4700:4700::1111"

# 检测IPv6支持
HAS_IPV6=false
if ip -6 addr show scope global 2>/dev/null | grep -q "inet6"; then
    HAS_IPV6=true
fi

# 检查DNS配置是否被修改
check_dns() {
    if ! grep -q "$PRIMARY_DNS" /etc/resolv.conf || ! grep -q "$SECONDARY_DNS" /etc/resolv.conf; then
        echo "检测到DNS配置被修改，正在恢复..."

        # 解除锁定
        chattr -i /etc/resolv.conf 2>/dev/null

        # 恢复配置
        cat > /etc/resolv.conf << DNS_RESTORE_EOF
# DNS配置 - 由setup_dns.sh脚本生成
# 请勿手动修改此文件
nameserver $PRIMARY_DNS
nameserver $SECONDARY_DNS
DNS_RESTORE_EOF

        # 如果支持IPv6,添加IPv6 DNS
        if [ "$HAS_IPV6" = "true" ]; then
            cat >> /etc/resolv.conf << DNS_RESTORE_V6_EOF
nameserver $PRIMARY_DNS_V6
nameserver $SECONDARY_DNS_V6
DNS_RESTORE_V6_EOF
        fi

        # 添加选项配置
        cat >> /etc/resolv.conf << DNS_RESTORE_OPT_EOF

# 选项配置
options timeout:2
options attempts:3
options rotate
options single-request-reopen
DNS_RESTORE_OPT_EOF

        # 重新锁定
        chattr +i /etc/resolv.conf 2>/dev/null
        echo "DNS配置已恢复"
    fi
}

check_dns
PROTECT_SCRIPT_EOF

    chmod +x /usr/local/bin/protect-dns.sh

    # 创建systemd服务来保护DNS
    cat > /etc/systemd/system/protect-dns.service << EOF
[Unit]
Description=Protect DNS Configuration
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/protect-dns.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # 创建定时器每分钟检查一次
    cat > /etc/systemd/system/protect-dns.timer << EOF
[Unit]
Description=Protect DNS Configuration Timer
Requires=protect-dns.service

[Timer]
OnCalendar=*:*:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # 启用服务和定时器
    systemctl daemon-reload
    systemctl enable protect-dns.service
    systemctl enable protect-dns.timer
    systemctl start protect-dns.timer

    log_info "DNS保护服务已启用，每分钟检查配置"
}

# 重启网络服务
restart_network() {
    log_step "重启网络服务..."

    case $OS in
        ubuntu|debian)
            if systemctl is-active --quiet NetworkManager; then
                systemctl restart NetworkManager
            else
                systemctl restart networking
            fi
            ;;
        centos|rhel|fedora)
            if systemctl is-active --quiet NetworkManager; then
                systemctl restart NetworkManager
            else
                systemctl restart network
            fi
            ;;
        arch)
            systemctl restart NetworkManager
            ;;
        *)
            log_warn "未知的操作系统，请手动重启网络服务"
            ;;
    esac

    sleep 3
}

# 测试DNS解析
test_dns() {
    log_step "测试DNS解析..."

    # 测试IPv4域名解析
    log_info "测试IPv4 DNS解析..."
    local test_domains=("google.com" "cloudflare.com" "github.com")
    local success_count=0

    for domain in "${test_domains[@]}"; do
        if nslookup $domain >/dev/null 2>&1; then
            log_info "✓ $domain IPv4 解析成功"
            ((success_count++))
        else
            log_error "✗ $domain IPv4 解析失败"
        fi
    done

    # 如果支持IPv6,测试IPv6解析
    if [ "$HAS_IPV6" = "true" ]; then
        log_info "测试IPv6 DNS解析..."
        local ipv6_success=0

        for domain in "${test_domains[@]}"; do
            # 使用dig查询AAAA记录
            if command -v dig >/dev/null 2>&1; then
                if dig @"$PRIMARY_DNS_V6" "$domain" AAAA +short +time=3 +tries=2 >/dev/null 2>&1; then
                    log_info "✓ $domain IPv6 解析成功"
                    ((ipv6_success++))
                else
                    log_warn "✗ $domain IPv6 解析失败"
                fi
            else
                log_warn "dig命令不可用，跳过IPv6解析测试"
                break
            fi
        done

        if [ $ipv6_success -gt 0 ]; then
            log_info "IPv6 DNS解析测试成功"
        fi
    fi

    if [ $success_count -eq ${#test_domains[@]} ]; then
        log_info "DNS配置测试完全成功！"
    elif [ $success_count -gt 0 ]; then
        log_warn "DNS配置部分成功，可能需要检查网络连接"
    else
        log_error "DNS配置失败，请检查网络设置"
        return 1
    fi
}

# 显示配置信息
show_config_info() {
    echo -e "\n${GREEN}=== DNS配置完成 ===${NC}"
    echo -e "${YELLOW}IPv4 DNS服务器:${NC}"
    echo -e "  主DNS: ${BLUE}$PRIMARY_DNS${NC} (Google DNS)"
    echo -e "  备DNS: ${BLUE}$SECONDARY_DNS${NC} (Cloudflare DNS)"

    if [ "$HAS_IPV6" = "true" ]; then
        echo -e "${YELLOW}IPv6 DNS服务器:${NC}"
        echo -e "  主DNS: ${BLUE}$PRIMARY_DNS_V6${NC} (Google DNS)"
        echo -e "  备DNS: ${BLUE}$SECONDARY_DNS_V6${NC} (Cloudflare DNS)"
    fi

    echo -e "${YELLOW}配置文件:${NC} ${BLUE}/etc/resolv.conf${NC}"
    echo -e "${YELLOW}保护状态:${NC} ${GREEN}已启用${NC}"
    echo -e "\n${YELLOW}注意事项:${NC}"
    echo -e "1. DNS配置已被锁定，系统会自动恢复任何修改"
    echo -e "2. 如需解锁，请运行: ${BLUE}chattr -i /etc/resolv.conf${NC}"
    echo -e "3. 如需停止保护，请运行: ${BLUE}systemctl stop protect-dns.timer${NC}"
    echo -e "4. 原始配置已备份到 /etc/resolv.conf.backup.*"
}

# 卸载功能
uninstall() {
    echo -e "${YELLOW}正在卸载DNS配置...${NC}"

    # 停止保护服务
    systemctl stop protect-dns.timer 2>/dev/null
    systemctl stop protect-dns.service 2>/dev/null
    systemctl disable protect-dns.timer 2>/dev/null
    systemctl disable protect-dns.service 2>/dev/null

    # 删除服务文件
    rm -f /etc/systemd/system/protect-dns.service
    rm -f /etc/systemd/system/protect-dns.timer
    rm -f /usr/local/bin/protect-dns.sh

    # 解锁resolv.conf
    chattr -i /etc/resolv.conf 2>/dev/null

    # 恢复原始配置
    local backup_file=$(ls /etc/resolv.conf.backup.* 2>/dev/null | tail -1)
    if [ -n "$backup_file" ]; then
        cp "$backup_file" /etc/resolv.conf
        log_info "已恢复原始DNS配置"
    fi

    # 重启网络
    restart_network

    log_info "DNS配置已卸载"
}

# 主函数
main() {
    echo -e "${GREEN}DNS配置脚本${NC}"
    echo -e "设置DNS为 8.8.8.8 和 1.1.1.1，支持IPv6，并防止更改"
    echo ""

    # 检查参数
    if [[ $1 == "--uninstall" ]]; then
        check_root
        uninstall
        exit 0
    fi

    # 检查权限
    check_root

    # 检测系统
    detect_os

    # 检测IPv6支持
    detect_ipv6

    # 执行配置步骤
    backup_config
    configure_dns_services
    configure_dns
    lock_dns_config
    restart_network

    # 测试DNS
    if test_dns; then
        show_config_info
        log_info "DNS配置成功完成！"
    else
        log_error "DNS配置可能存在问题，请检查网络设置"
        exit 1
    fi
}

# 信号处理
trap 'log_error "脚本被中断"; exit 1' INT TERM

# 运行主函数
main "$@"