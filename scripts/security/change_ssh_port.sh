#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SSHD_CONFIG="/etc/ssh/sshd_config"

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

# 获取当前SSH端口
get_current_port() {
    local port
    # 优先读取未注释的 Port 行
    port=$(grep -E '^\s*Port\s+' "$SSHD_CONFIG" 2>/dev/null | awk '{print $2}' | head -n1)
    if [[ -z "$port" ]]; then
        port=22
    fi
    echo "$port"
}

# 验证端口号
validate_port() {
    local port="$1"
    if [[ ! "$port" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    if [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
        return 1
    fi
    return 0
}

# 检查端口是否被其他服务占用
check_port_in_use() {
    local port="$1"
    local current_port
    current_port=$(get_current_port)

    # 如果是当前SSH端口，不算占用
    if [[ "$port" == "$current_port" ]]; then
        return 1
    fi

    # 检查端口是否被监听
    if command -v ss >/dev/null 2>&1; then
        if ss -tlnp 2>/dev/null | grep -q ":${port}\b"; then
            return 0
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tlnp 2>/dev/null | grep -q ":${port}\b"; then
            return 0
        fi
    fi
    return 1
}

# 备份sshd_config
backup_config() {
    local backup_dir="/etc/ssh/backup"
    local backup_file="$backup_dir/sshd_config.backup.$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    cp "$SSHD_CONFIG" "$backup_file"
    echo_info "已备份配置到: $backup_file"
}

# 修改SSH端口
change_port() {
    local new_port="$1"

    if grep -qE '^\s*Port\s+' "$SSHD_CONFIG"; then
        # 替换已有的 Port 行
        sed -i "s/^\s*Port\s\+.*/Port $new_port/" "$SSHD_CONFIG"
    elif grep -qE '^\s*#\s*Port\s+' "$SSHD_CONFIG"; then
        # 取消注释并修改
        sed -i "s/^\s*#\s*Port\s\+.*/Port $new_port/" "$SSHD_CONFIG"
    else
        # 添加 Port 配置
        echo "Port $new_port" >> "$SSHD_CONFIG"
    fi
}

# 处理SELinux
handle_selinux() {
    local port="$1"

    if ! command -v getenforce >/dev/null 2>&1; then
        return
    fi

    local se_status
    se_status=$(getenforce 2>/dev/null || echo "Disabled")
    if [[ "$se_status" == "Disabled" || "$se_status" == "Permissive" ]]; then
        return
    fi

    echo_info "检测到SELinux处于Enforcing模式"

    if command -v semanage >/dev/null 2>&1; then
        echo_info "正在为SELinux放行端口 $port..."
        semanage port -a -t ssh_port_t -p tcp "$port" 2>/dev/null || \
        semanage port -m -t ssh_port_t -p tcp "$port" 2>/dev/null || true
        echo_info "SELinux端口已放行"
    else
        echo_warn "未安装 semanage 工具，请手动放行SELinux端口:"
        echo_warn "  yum install -y policycoreutils-python-utils"
        echo_warn "  semanage port -a -t ssh_port_t -p tcp $port"
    fi
}

# 处理防火墙
handle_firewall() {
    local port="$1"

    # UFW
    if command -v ufw >/dev/null 2>&1; then
        if ufw status 2>/dev/null | grep -q "Status: active"; then
            echo_info "检测到UFW防火墙已启用，正在放行端口 $port..."
            ufw allow "$port/tcp" comment 'SSH' >/dev/null 2>&1
            echo_info "UFW已放行端口 $port"
        fi
    fi

    # firewalld
    if command -v firewall-cmd >/dev/null 2>&1; then
        if systemctl is-active --quiet firewalld 2>/dev/null; then
            echo_info "检测到firewalld已启用，正在放行端口 $port..."
            firewall-cmd --permanent --add-port="$port/tcp" >/dev/null 2>&1
            firewall-cmd --reload >/dev/null 2>&1
            echo_info "firewalld已放行端口 $port"
        fi
    fi

    # iptables (无ufw/firewalld时)
    if ! command -v ufw >/dev/null 2>&1 && ! command -v firewall-cmd >/dev/null 2>&1; then
        if command -v iptables >/dev/null 2>&1; then
            echo_warn "未检测到UFW或firewalld，请手动确认iptables规则允许端口 $port"
        fi
    fi
}

# 验证sshd配置
verify_config() {
    echo_info "验证SSH配置语法..."
    if sshd -t 2>/dev/null; then
        echo_info "配置语法验证通过"
        return 0
    else
        echo_error "配置语法验证失败！"
        return 1
    fi
}

# 重启SSH服务
restart_sshd() {
    echo_info "正在重启SSH服务..."
    if systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null; then
        echo_info "SSH服务已重启"
    else
        echo_error "SSH服务重启失败"
        return 1
    fi
}

# 显示当前状态
show_status() {
    local current_port
    current_port=$(get_current_port)
    echo ""
    echo "════════════════════════════════════"
    echo "  SSH 端口管理"
    echo "════════════════════════════════════"
    echo -e "  当前SSH端口: ${GREEN}$current_port${NC}"
    echo "────────────────────────────────────"
}

main() {
    check_root

    if [[ ! -f "$SSHD_CONFIG" ]]; then
        echo_error "未找到SSH配置文件: $SSHD_CONFIG"
        exit 1
    fi

    show_status

    local current_port
    current_port=$(get_current_port)

    echo ""
    read -p "请输入新的SSH端口号 (1-65535, 当前: $current_port): " new_port

    # 验证端口
    if ! validate_port "$new_port"; then
        echo_error "无效端口号: $new_port (范围: 1-65535)"
        exit 1
    fi

    if [[ "$new_port" == "$current_port" ]]; then
        echo_info "新端口与当前端口相同，无需修改"
        exit 0
    fi

    # 检查端口占用
    if check_port_in_use "$new_port"; then
        echo_error "端口 $new_port 已被其他服务占用"
        exit 1
    fi

    # 常用端口警告
    if [[ "$new_port" -le 1024 && "$new_port" -ne 22 ]]; then
        echo_warn "端口 $new_port 是特权端口 (<=1024)，可能与其他服务冲突"
        read -p "是否继续? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[yY]$ ]]; then
            echo_info "已取消"
            exit 0
        fi
    fi

    echo ""
    echo_warn "即将执行以下操作:"
    echo "  1. 备份当前SSH配置"
    echo "  2. 将SSH端口从 $current_port 修改为 $new_port"
    echo "  3. 放行防火墙端口 (如适用)"
    echo "  4. 验证配置并重启SSH服务"
    echo ""
    echo_warn "请确保你有其他方式访问服务器 (如VNC/控制台)，以防SSH连接中断！"
    read -p "确认修改? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[yY]$ ]]; then
        echo_info "已取消"
        exit 0
    fi

    # 执行修改
    echo ""
    backup_config
    change_port "$new_port"

    # 验证配置
    if ! verify_config; then
        echo_error "配置验证失败，正在恢复备份..."
        local latest_backup
        latest_backup=$(ls -t /etc/ssh/backup/sshd_config.backup.* 2>/dev/null | head -n1)
        if [[ -n "$latest_backup" ]]; then
            cp "$latest_backup" "$SSHD_CONFIG"
            echo_info "已恢复备份配置"
        fi
        exit 1
    fi

    # 处理SELinux和防火墙
    handle_selinux "$new_port"
    handle_firewall "$new_port"

    # 重启SSH
    restart_sshd

    echo ""
    echo_info "SSH端口已成功修改为: $new_port"
    echo_warn "请使用新端口测试连接: ssh -p $new_port user@host"
    echo_warn "确认新端口可用后，建议在防火墙中移除旧端口 $current_port 的放行规则"
}

main "$@"
