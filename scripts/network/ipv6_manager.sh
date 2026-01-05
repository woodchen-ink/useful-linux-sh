#!/bin/bash

# IPv6管理工具 - 支持IPv4优先级调整和IPv6禁用
# 用途: 解决IPv6网络环境下的连接问题,提供灵活的网络配置选项

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[信息]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

log_error() {
    echo -e "${RED}[错误]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用root权限运行此脚本"
        exit 1
    fi
}

# 备份配置文件
backup_config() {
    local file=$1
    local backup_file="${file}.backup.$(date +%Y%m%d_%H%M%S)"

    if [ -f "$file" ]; then
        cp "$file" "$backup_file"
        log_info "已备份配置文件: $backup_file"
    fi
}

# 获取当前IPv6状态
get_ipv6_status() {
    if [ -f /proc/sys/net/ipv6/conf/all/disable_ipv6 ]; then
        local status=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6)
        if [ "$status" = "1" ]; then
            echo "已禁用"
        else
            echo "已启用"
        fi
    else
        echo "未知"
    fi
}

# 获取当前地址族优先级
get_precedence_status() {
    if [ -f /etc/gai.conf ]; then
        if grep -q "^precedence ::ffff:0:0/96  100" /etc/gai.conf; then
            echo "IPv4优先"
        else
            echo "默认配置"
        fi
    else
        echo "配置文件不存在"
    fi
}

# 设置IPv4优先级
set_ipv4_priority() {
    log_info "开始设置IPv4优先级..."

    # 备份gai.conf
    backup_config "/etc/gai.conf"

    # 创建或修改gai.conf
    cat > /etc/gai.conf << 'EOF_GAI'
# Configuration for getaddrinfo(3).
# 此配置使IPv4地址优先于IPv6地址

# IPv4地址优先级设置为100
precedence ::ffff:0:0/96  100

# IPv6地址优先级设置较低
precedence ::/0           50
precedence 2002::/16      30
precedence ::/96          20
precedence ::1/128        10
EOF_GAI

    if [ $? -eq 0 ]; then
        log_success "IPv4优先级配置已生效"
        log_info "当前配置: IPv4优先于IPv6"
        return 0
    else
        log_error "IPv4优先级配置失败"
        return 1
    fi
}

# 恢复默认优先级
restore_default_priority() {
    log_info "开始恢复默认地址族优先级..."

    if [ -f /etc/gai.conf ]; then
        backup_config "/etc/gai.conf"

        # 恢复为注释状态或删除文件
        cat > /etc/gai.conf << 'EOF_GAI_DEFAULT'
# Configuration for getaddrinfo(3).
# 默认配置 - IPv6和IPv4按系统默认规则处理

# precedence ::ffff:0:0/96  100
EOF_GAI_DEFAULT

        log_success "已恢复默认地址族优先级"
    else
        log_warning "/etc/gai.conf 文件不存在,无需恢复"
    fi
}

# 禁用IPv6
disable_ipv6() {
    log_info "开始禁用IPv6..."

    # 方法1: 通过sysctl禁用
    log_info "配置sysctl参数..."
    cat >> /etc/sysctl.conf << 'EOF_SYSCTL'

# 禁用IPv6配置
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF_SYSCTL

    # 立即应用sysctl配置
    sysctl -p > /dev/null 2>&1

    # 方法2: 通过GRUB禁用(更彻底)
    if [ -f /etc/default/grub ]; then
        log_info "配置GRUB参数..."
        backup_config "/etc/default/grub"

        # 检查是否已存在ipv6.disable参数
        if grep -q "ipv6.disable=1" /etc/default/grub; then
            log_info "GRUB已配置IPv6禁用参数"
        else
            # 添加ipv6.disable=1到GRUB_CMDLINE_LINUX
            sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 ipv6.disable=1"/' /etc/default/grub

            # 更新GRUB
            if command -v update-grub > /dev/null 2>&1; then
                update-grub > /dev/null 2>&1
            elif command -v grub2-mkconfig > /dev/null 2>&1; then
                grub2-mkconfig -o /boot/grub2/grub.cfg > /dev/null 2>&1
            elif command -v grub-mkconfig > /dev/null 2>&1; then
                grub-mkconfig -o /boot/grub/grub.cfg > /dev/null 2>&1
            fi
        fi
    fi

    log_success "IPv6已禁用"
    log_warning "完整禁用IPv6需要重启系统才能生效"
    log_info "当前会话已通过sysctl禁用IPv6"
}

# 启用IPv6
enable_ipv6() {
    log_info "开始启用IPv6..."

    # 恢复sysctl配置
    log_info "移除sysctl禁用配置..."
    if [ -f /etc/sysctl.conf ]; then
        backup_config "/etc/sysctl.conf"
        sed -i '/net.ipv6.conf.all.disable_ipv6/d' /etc/sysctl.conf
        sed -i '/net.ipv6.conf.default.disable_ipv6/d' /etc/sysctl.conf
        sed -i '/net.ipv6.conf.lo.disable_ipv6/d' /etc/sysctl.conf
        sed -i '/# 禁用IPv6配置/d' /etc/sysctl.conf
    fi

    # 立即启用IPv6
    sysctl -w net.ipv6.conf.all.disable_ipv6=0 > /dev/null 2>&1
    sysctl -w net.ipv6.conf.default.disable_ipv6=0 > /dev/null 2>&1
    sysctl -w net.ipv6.conf.lo.disable_ipv6=0 > /dev/null 2>&1

    # 恢复GRUB配置
    if [ -f /etc/default/grub ]; then
        log_info "移除GRUB禁用配置..."
        backup_config "/etc/default/grub"
        sed -i 's/ ipv6.disable=1//g' /etc/default/grub

        # 更新GRUB
        if command -v update-grub > /dev/null 2>&1; then
            update-grub > /dev/null 2>&1
        elif command -v grub2-mkconfig > /dev/null 2>&1; then
            grub2-mkconfig -o /boot/grub2/grub.cfg > /dev/null 2>&1
        elif command -v grub-mkconfig > /dev/null 2>&1; then
            grub-mkconfig -o /boot/grub/grub.cfg > /dev/null 2>&1
        fi
    fi

    log_success "IPv6已启用"
    log_warning "完整启用IPv6需要重启系统才能生效"
    log_info "当前会话已通过sysctl启用IPv6"
}

# 显示当前状态
show_status() {
    echo ""
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${BLUE}     IPv6配置状态${NC}"
    echo -e "${BLUE}=====================================${NC}"

    local ipv6_status=$(get_ipv6_status)
    local precedence_status=$(get_precedence_status)

    echo -e "${GREEN}IPv6状态:${NC} $ipv6_status"
    echo -e "${GREEN}地址族优先级:${NC} $precedence_status"

    # 显示当前IPv4和IPv6地址
    echo ""
    echo -e "${BLUE}当前网络地址:${NC}"
    ip -4 addr show | grep inet | grep -v 127.0.0.1 | awk '{print "  IPv4: " $2}'
    ip -6 addr show | grep inet6 | grep -v "::1" | grep -v "fe80" | awk '{print "  IPv6: " $2}'

    echo -e "${BLUE}=====================================${NC}"
    echo ""
}

# 主菜单
show_menu() {
    clear
    echo -e "${GREEN}=====================================${NC}"
    echo -e "${GREEN}     IPv6管理工具${NC}"
    echo -e "${GREEN}=====================================${NC}"
    echo ""
    echo "1. 设置IPv4优先级 (保留IPv6,但优先使用IPv4)"
    echo "2. 恢复默认优先级"
    echo "3. 禁用IPv6 (完全禁用IPv6)"
    echo "4. 启用IPv6"
    echo "5. 查看当前状态"
    echo "0. 退出"
    echo ""
    echo -e "${YELLOW}当前状态:${NC} IPv6 $(get_ipv6_status) | 优先级 $(get_precedence_status)"
    echo ""
}

# 主函数
main() {
    check_root

    while true; do
        show_menu
        read -p "请选择操作 [0-5]: " choice

        case $choice in
            1)
                set_ipv4_priority
                show_status
                read -p "按回车键继续..."
                ;;
            2)
                restore_default_priority
                show_status
                read -p "按回车键继续..."
                ;;
            3)
                echo ""
                log_warning "禁用IPv6可能影响某些需要IPv6的应用"
                read -p "确认要禁用IPv6吗? (y/N): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    disable_ipv6
                    show_status
                else
                    log_info "操作已取消"
                fi
                read -p "按回车键继续..."
                ;;
            4)
                enable_ipv6
                show_status
                read -p "按回车键继续..."
                ;;
            5)
                show_status
                read -p "按回车键继续..."
                ;;
            0)
                log_info "退出IPv6管理工具"
                exit 0
                ;;
            *)
                log_error "无效的选择,请重新输入"
                sleep 2
                ;;
        esac
    done
}

# 执行主函数
main
