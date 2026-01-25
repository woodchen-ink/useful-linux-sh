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

check_existing_fail2ban() {
    if command -v fail2ban-server >/dev/null 2>&1; then
        echo_info "检测到Fail2ban已安装"

        # 检查Fail2ban服务状态
        if systemctl is-active --quiet fail2ban 2>/dev/null; then
            echo_warn "检测到Fail2ban服务已运行"

            # 备份当前配置
            local jail_local="/etc/fail2ban/jail.local"
            local backup_dir="/etc/fail2ban/backup"
            local backup_file="$backup_dir/jail.local.backup.$(date +%Y%m%d_%H%M%S)"

            mkdir -p "$backup_dir"

            if [[ -f "$jail_local" ]]; then
                cp "$jail_local" "$backup_file"
                echo_info "已备份当前配置到: $backup_file"
            fi

            # 备份当前封禁列表
            local ban_list="$backup_dir/banned_ips.$(date +%Y%m%d_%H%M%S).txt"
            fail2ban-client status sshd 2>/dev/null | grep "Banned IP list" > "$ban_list" || true
            echo_info "已备份当前封禁IP列表到: $ban_list"

            # 询问用户是否继续
            echo ""
            echo_warn "继续执行将覆盖现有配置！"
            echo "1) 覆盖并重新配置"
            echo "2) 保留现有配置并退出"
            read -p "请选择 [1-2]: " choice

            case $choice in
                1)
                    echo_info "用户选择覆盖配置"
                    return 0
                    ;;
                2)
                    echo_info "保留现有配置，退出脚本"
                    exit 0
                    ;;
                *)
                    echo_error "无效选择，退出脚本"
                    exit 1
                    ;;
            esac
        fi
        return 0
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
        return 0
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
    check_existing_fail2ban
    configure_fail2ban
    enable_fail2ban

    echo ""
    echo_info "Fail2ban配置完成！"
    echo_info "已设置永久封禁模式 (bantime = -1)"
    echo_warn "被封禁的IP需要手动解封: fail2ban-client unban <IP>"
    echo_info "如需恢复旧配置，请查看备份文件: /etc/fail2ban/backup/"
}

main "$@"