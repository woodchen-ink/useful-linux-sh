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

install_ufw() {
    if command -v ufw >/dev/null 2>&1; then
        echo_info "检测到UFW已安装"
        return 0
    fi

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
}

is_ufw_active() {
    systemctl is-active --quiet ufw 2>/dev/null || ufw status 2>/dev/null | grep -q "Status: active"
}

list_rules() {
    echo ""
    echo_info "当前UFW规则:"
    echo "─────────────────────────────────────────"
    ufw status numbered
    echo "─────────────────────────────────────────"
}

delete_port_rule() {
    list_rules
    echo ""
    echo "请输入要删除的规则编号 (如: 3)"
    echo "提示: 每次只能删除一条，删除后编号会变化"
    read -p "规则编号: " rule_num

    if [[ ! "$rule_num" =~ ^[0-9]+$ ]]; then
        echo_warn "无效编号"
        return
    fi

    echo_warn "即将删除规则 #$rule_num"
    read -p "确认删除? [y/N]: " confirm
    if [[ "$confirm" =~ ^[yY]$ ]]; then
        yes | ufw delete "$rule_num" && echo_info "规则已删除" || echo_error "删除失败"
    else
        echo_info "已取消"
    fi
}

manage_menu() {
    while true; do
        echo ""
        echo "════════════════════════════════════"
        echo "  UFW 防火墙管理"
        echo "════════════════════════════════════"
        echo "  1) 新增端口放行规则"
        echo "  2) 删除端口规则"
        echo "  3) 列出当前规则"
        echo "  4) 重置并重新配置"
        echo "  0) 退出"
        echo "────────────────────────────────────"
        read -p "请选择 [0-4]: " choice

        case "$choice" in
            1)
                read -p "请输入端口号: " port
                if validate_port "$port"; then
                    allow_port_with_options "$port"
                else
                    echo_warn "无效端口: $port"
                fi
                ;;
            2)
                delete_port_rule
                ;;
            3)
                list_rules
                ;;
            4)
                echo_warn "此操作将重置所有现有规则！"
                read -p "确认重置? [y/N]: " confirm
                if [[ "$confirm" =~ ^[yY]$ ]]; then
                    configure_default_ports
                    ask_additional_ports
                    enable_ufw
                    echo_info "重置配置完成"
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

validate_port() {
    local port="$1"
    if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    fi
    return 1
}

validate_ip() {
    local ip="$1"
    # IPv4
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    fi
    # IPv4 CIDR
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        return 0
    fi
    # IPv6 (简单校验含冒号即视为IPv6)
    if [[ "$ip" =~ : ]]; then
        return 0
    fi
    return 1
}

add_ufw_rule() {
    local port="$1"
    local from_addr="$2"
    local comment="$3"

    if [[ -n "$from_addr" ]]; then
        ufw allow proto tcp from "$from_addr" to any port "$port" comment "$comment"
    else
        ufw allow "$port" comment "$comment"
    fi
}

allow_port_rule() {
    local port="$1"
    local ip_version="$2"
    local ip_addr="$3"

    case "$ip_version" in
        v4)
            if [[ -n "$ip_addr" ]]; then
                add_ufw_rule "$port" "$ip_addr" "Port $port from $ip_addr"
            else
                # 使用 0.0.0.0/0 限定仅 IPv4
                add_ufw_rule "$port" "0.0.0.0/0" "Port $port (IPv4 only)"
            fi
            ;;
        v6)
            if [[ -n "$ip_addr" ]]; then
                add_ufw_rule "$port" "$ip_addr" "Port $port from $ip_addr"
            else
                # 使用 ::/0 限定仅 IPv6
                add_ufw_rule "$port" "::/0" "Port $port (IPv6 only)"
            fi
            ;;
        both)
            if [[ -n "$ip_addr" ]]; then
                add_ufw_rule "$port" "$ip_addr" "Port $port from $ip_addr"
            else
                add_ufw_rule "$port" "" "Port $port"
            fi
            ;;
    esac
}

allow_port_with_options() {
    local port="$1"

    # 选择IP版本
    echo ""
    echo "端口 $port 放行选项:"
    echo "  1) 仅 IPv4"
    echo "  2) 仅 IPv6"
    echo "  3) IPv4 + IPv6 (默认)"
    read -p "请选择 [1-3, 默认3]: " ip_choice
    ip_choice=${ip_choice:-3}

    local ip_version
    case "$ip_choice" in
        1) ip_version="v4" ;;
        2) ip_version="v6" ;;
        *) ip_version="both" ;;
    esac

    # 选择IP限制
    echo ""
    echo "放行范围:"
    echo "  1) 所有IP (默认)"
    echo "  2) 指定IP地址 (支持单个或多个, 支持CIDR)"
    read -p "请选择 [1-2, 默认1]: " scope_choice
    scope_choice=${scope_choice:-1}

    case "$scope_choice" in
        2)
            echo "请输入IP地址，多个IP用空格分隔"
            echo "示例: 192.168.1.100 10.0.0.0/24 2001:db8::1"
            read -r ip_list

            if [[ -z "$ip_list" ]]; then
                echo_warn "未输入IP，将放行所有IP"
                allow_port_rule "$port" "$ip_version" ""
                echo_info "已放行端口 $port ($ip_version) - 所有IP"
            else
                for ip in $ip_list; do
                    if validate_ip "$ip"; then
                        allow_port_rule "$port" "$ip_version" "$ip"
                        echo_info "已放行端口 $port ($ip_version) - 来源: $ip"
                    else
                        echo_warn "无效IP: $ip，跳过"
                    fi
                done
            fi
            ;;
        *)
            allow_port_rule "$port" "$ip_version" ""
            echo_info "已放行端口 $port ($ip_version) - 所有IP"
            ;;
    esac
}

ask_additional_ports() {
    while true; do
        echo ""
        echo_warn "是否需要放行其他端口？"
        echo "1) 添加端口放行规则"
        echo "2) 完成，不再添加"
        read -p "请选择 [1-2]: " add_choice

        case "$add_choice" in
            1)
                read -p "请输入端口号: " port
                if validate_port "$port"; then
                    allow_port_with_options "$port"
                else
                    echo_warn "无效端口: $port"
                fi
                ;;
            2|"")
                echo_info "端口配置完成"
                break
                ;;
            *)
                echo_warn "无效选择"
                ;;
        esac
    done
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
    check_root
    install_ufw

    if is_ufw_active; then
        echo_info "UFW服务已运行，进入管理菜单"
        manage_menu
    else
        echo_info "首次配置UFW防火墙..."
        configure_default_ports
        ask_additional_ports
        enable_ufw
        echo ""
        echo_info "UFW防火墙配置完成！"
        echo_info "当前防火墙规则已生效，SSH连接不会中断"
    fi
}

main "$@"