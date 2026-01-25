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

check_existing_ufw() {
    if command -v ufw >/dev/null 2>&1; then
        echo_info "检测到UFW已安装"

        # 检查UFW服务状态
        if systemctl is-active --quiet ufw 2>/dev/null || ufw status | grep -q "Status: active"; then
            echo_warn "检测到UFW服务已运行"

            # 备份当前规则
            local backup_dir="/etc/ufw/backup"
            local backup_file="$backup_dir/rules.backup.$(date +%Y%m%d_%H%M%S)"

            mkdir -p "$backup_dir"
            ufw status numbered > "$backup_file" 2>/dev/null || true
            echo_info "已备份当前规则到: $backup_file"

            # 询问用户是否继续
            echo ""
            echo_warn "继续执行将重置所有现有规则！"
            echo "1) 重置并重新配置"
            echo "2) 保留现有配置并退出"
            read -p "请选择 [1-2]: " choice

            case $choice in
                1)
                    echo_info "用户选择重置配置"
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
        echo_info "UFW未安装，开始安装..."

        if command -v apt >/dev/null 2>&1; then
            apt update
            apt install -y ufw
        elif command -v yum >/dev/null 2>&1; then
            yum install -y epel-release
            yum install -y ufw
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y ufw
        elif command -v pacman >/dev/null 2>&1; then
            pacman -Sy --noconfirm ufw
        else
            echo_error "不支持的包管理器，请手动安装UFW"
            exit 1
        fi

        echo_info "UFW安装完成"
        return 0
    fi
}

configure_default_ports() {
    echo_info "配置默认端口..."
    
    ufw --force reset
    
    ufw default deny incoming
    ufw default allow outgoing
    
    ufw allow 22/tcp comment 'SSH'
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    
    echo_info "已放行默认端口: 22(SSH), 80(HTTP), 443(HTTPS)"
}

ask_additional_ports() {
    echo ""
    echo_warn "是否需要放行其他端口？"
    echo "请输入端口号，多个端口用空格分隔（如: 3000 8080 9000）"
    echo "直接回车跳过："
    
    read -r additional_ports
    
    if [[ -n "$additional_ports" ]]; then
        for port in $additional_ports; do
            if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
                ufw allow "$port" comment "Custom port $port"
                echo_info "已放行端口: $port"
            else
                echo_warn "无效端口: $port，跳过"
            fi
        done
    else
        echo_info "未添加额外端口"
    fi
}

enable_ufw() {
    echo_info "启用UFW防火墙..."
    ufw --force enable
    
    echo_info "设置UFW开机自启..."
    systemctl enable ufw
    
    echo_info "UFW状态:"
    ufw status verbose
}

main() {
    echo_info "开始配置UFW防火墙..."

    check_root
    check_existing_ufw
    configure_default_ports
    ask_additional_ports
    enable_ufw

    echo ""
    echo_info "UFW防火墙配置完成！"
    echo_info "当前防火墙规则已生效，SSH连接不会中断"
    echo_info "如需恢复旧规则，请查看备份文件: /etc/ufw/backup/"
}

main "$@"