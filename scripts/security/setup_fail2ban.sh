#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

JAIL_LOCAL="/etc/fail2ban/jail.local"

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

install_fail2ban() {
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
}

get_ssh_port() {
    local port
    port=$(grep -E '^[[:space:]]*Port[[:space:]]+' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -n1)
    if [[ -z "$port" ]]; then
        port=22
    fi
    echo "$port"
}

get_fail2ban_port() {
    local port
    port=$(grep -E '^[[:space:]]*port[[:space:]]*=' "$JAIL_LOCAL" 2>/dev/null | awk -F'=' '{print $2}' | tr -d ' ' | head -n1)
    if [[ -z "$port" ]]; then
        port="未配置"
    fi
    echo "$port"
}

backup_config() {
    local backup_dir="/etc/fail2ban/backup"
    mkdir -p "$backup_dir"

    if [[ -f "$JAIL_LOCAL" ]]; then
        local backup_file="$backup_dir/jail.local.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$JAIL_LOCAL" "$backup_file"
        echo_info "已备份配置到: $backup_file"
    fi
}

configure_fail2ban() {
    local ssh_port
    ssh_port=$(get_ssh_port)

    echo_info "检测到当前SSH端口: $ssh_port"
    echo_info "创建jail.local配置文件"
    cat > "$JAIL_LOCAL" <<EOF
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
port = $ssh_port
maxretry = 5
findtime = 300s
bantime = -1
banaction = ufw
action = %(action_mwl)s
logpath = /var/log/auth.log
EOF

    echo_info "Fail2ban配置完成 (SSH永久封禁模式, 监控端口: $ssh_port)"
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

# 修改监听端口
change_port() {
    local current_f2b_port
    current_f2b_port=$(get_fail2ban_port)
    local ssh_port
    ssh_port=$(get_ssh_port)

    echo ""
    echo_info "当前Fail2ban监听端口: $current_f2b_port"
    echo_info "当前SSH实际端口: $ssh_port"

    echo ""
    echo "选择操作(更新端口并重启会比较久, 请耐心等待):"
    echo "  1) 自动同步为当前SSH端口 ($ssh_port)"
    echo "  2) 手动输入端口"
    read -p "请选择 [1-2]: " port_choice

    local new_port
    case "$port_choice" in
        1)
            new_port="$ssh_port"
            ;;
        2)
            read -p "请输入新端口号: " new_port
            if [[ ! "$new_port" =~ ^[0-9]+$ ]] || [[ "$new_port" -lt 1 || "$new_port" -gt 65535 ]]; then
                echo_warn "无效端口号"
                return
            fi
            ;;
        *)
            echo_warn "无效选择"
            return
            ;;
    esac

    if [[ "$new_port" == "$current_f2b_port" ]]; then
        echo_info "端口未变化，无需修改"
        return
    fi

    if grep -qE '^[[:space:]]*port[[:space:]]*=' "$JAIL_LOCAL"; then
        sed -i -E "s/^([[:space:]]*port[[:space:]]*=).*/\1 $new_port/" "$JAIL_LOCAL"
    fi

    systemctl restart fail2ban
    echo_info "Fail2ban监听端口已更新为: $new_port"
}

# 管理菜单
manage_menu() {
    while true; do
        local f2b_port
        f2b_port=$(get_fail2ban_port)
        local ssh_port
        ssh_port=$(get_ssh_port)

        echo ""
        echo "════════════════════════════════════"
        echo "  Fail2ban 管理"
        echo "════════════════════════════════════"
        echo -e "  监听端口: ${GREEN}$f2b_port${NC}"
        echo -e "  SSH端口:  ${GREEN}$ssh_port${NC}"
        if [[ "$f2b_port" != "$ssh_port" ]]; then
            echo -e "  ${YELLOW}[!] 端口不一致，建议同步${NC}"
        fi
        echo "────────────────────────────────────"
        echo "  1) 修改监听端口"
        echo "  2) 查看封禁状态"
        echo "  3) 重新配置 (覆盖现有配置)"
        echo "  0) 退出"
        echo "────────────────────────────────────"
        read -p "请选择 [0-3]: " choice

        case "$choice" in
            1)
                change_port
                ;;
            2)
                echo ""
                fail2ban-client status sshd 2>/dev/null || echo_warn "sshd jail 未运行"
                ;;
            3)
                echo_warn "此操作将覆盖现有配置！"
                read -p "确认? [y/N]: " confirm
                if [[ "$confirm" =~ ^[yY]$ ]]; then
                    backup_config
                    configure_fail2ban
                    enable_fail2ban
                    echo_info "重新配置完成"
                else
                    echo_info "已取消"
                fi
                ;;
            0)
                echo_info "退出"
                exit 0
                ;;
            *)
                echo_warn "无效选择"
                ;;
        esac
    done
}

main() {
    check_root

    if command -v fail2ban-server >/dev/null 2>&1 && systemctl is-active --quiet fail2ban 2>/dev/null; then
        echo_info "Fail2ban已安装且运行中，进入管理菜单"
        manage_menu
    else
        if ! command -v fail2ban-server >/dev/null 2>&1; then
            install_fail2ban
        fi
        backup_config
        configure_fail2ban
        enable_fail2ban

        echo ""
        echo_info "Fail2ban配置完成！"
        echo_info "已设置永久封禁模式 (bantime = -1)"
        echo_warn "被封禁的IP需要手动解封: fail2ban-client unban <IP>"
        echo_info "如需恢复旧配置，请查看备份文件: /etc/fail2ban/backup/"
    fi
}

main "$@"
