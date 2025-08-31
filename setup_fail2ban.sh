#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo_error "此脚本需要root权限运行"
        exit 1
    fi
}

check_and_install_fail2ban() {
    if command -v fail2ban-server >/dev/null 2>&1; then
        echo_info "Fail2ban已安装"
    else
        echo_info "Fail2ban未安装，开始安装..."
        
        if command -v apt >/dev/null 2>&1; then
            apt update
            apt install -y fail2ban
        elif command -v yum >/dev/null 2>&1; then
            yum install -y epel-release
            yum install -y fail2ban
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y fail2ban
        elif command -v pacman >/dev/null 2>&1; then
            pacman -Sy --noconfirm fail2ban
        else
            echo_error "不支持的包管理器，请手动安装Fail2ban"
            exit 1
        fi
        
        echo_info "Fail2ban安装完成"
    fi
}

configure_fail2ban() {
    echo_info "配置Fail2ban..."
    
    local jail_local="/etc/fail2ban/jail.local"
    
    echo_info "创建jail.local配置文件"
    cat > "$jail_local" << 'EOF'
#DEFAULT-START
[DEFAULT]
bantime = 600
findtime = 300
maxretry = 5
banaction = ufw
action = %(action_mwl)s
#DEFAULT-END

[sshd]
ignoreip = 127.0.0.1/8
enabled = true
filter = sshd
port = 22
maxretry = 5
findtime = 300s
bantime = -1
banaction = ufw
action = %(action_mwl)s
logpath = /var/log/auth.log
EOF
    
    echo_info "Fail2ban配置完成 (SSH永久封禁模式)"
}

enable_fail2ban() {
    echo_info "启动Fail2ban服务..."
    systemctl enable fail2ban
    systemctl restart fail2ban
    
    echo_info "Fail2ban状态:"
    systemctl status fail2ban --no-pager -l
    
    echo ""
    echo_info "当前活跃的jail:"
    fail2ban-client status
}

main() {
    echo_info "开始配置Fail2ban..."
    
    check_root
    check_and_install_fail2ban
    configure_fail2ban
    enable_fail2ban
    
    echo ""
    echo_info "Fail2ban配置完成！"
    echo_info "已设置永久封禁模式 (bantime = -1)"
    echo_warn "被封禁的IP需要手动解封: fail2ban-client unban <IP>"
}

main "$@"