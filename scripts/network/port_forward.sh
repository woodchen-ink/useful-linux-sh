#!/bin/bash

# 端口转发管理脚本
# 使用iptables实现端口转发功能

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 配置文件路径
CONFIG_FILE="/etc/uls/port_forward.conf"

# 日志函数
echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo_error "此脚本需要root权限运行"
        exit 1
    fi
}

# 检查并安装必要工具
check_requirements() {
    if ! command -v iptables >/dev/null 2>&1; then
        echo_error "iptables未安装，请先安装iptables"
        exit 1
    fi

    # 创建配置目录
    mkdir -p "$(dirname "$CONFIG_FILE")"
    touch "$CONFIG_FILE"
}

# 启用IP转发
enable_ip_forward() {
    echo_info "检查IP转发状态..."

    if [ "$(cat /proc/sys/net/ipv4/ip_forward)" -eq 0 ]; then
        echo_warn "IP转发未启用，正在启用..."

        # 临时启用
        echo 1 > /proc/sys/net/ipv4/ip_forward

        # 永久启用
        if grep -q "^net.ipv4.ip_forward" /etc/sysctl.conf; then
            sed -i 's/^net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/sysctl.conf
        else
            echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
        fi

        echo_success "IP转发已启用"
    else
        echo_info "IP转发已启用"
    fi
}

# 验证IP地址格式
validate_ip() {
    local ip=$1
    local valid_ip_regex="^([0-9]{1,3}\.){3}[0-9]{1,3}$"

    if [[ ! $ip =~ $valid_ip_regex ]]; then
        return 1
    fi

    # 检查每个数字是否在0-255范围内
    IFS='.' read -ra ADDR <<< "$ip"
    for i in "${ADDR[@]}"; do
        if [ "$i" -gt 255 ]; then
            return 1
        fi
    done

    return 0
}

# 验证端口号
validate_port() {
    local port=$1
    if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    else
        return 1
    fi
}

# 验证协议
validate_protocol() {
    local proto=$1
    if [[ "$proto" == "tcp" ]] || [[ "$proto" == "udp" ]] || [[ "$proto" == "both" ]]; then
        return 0
    else
        return 1
    fi
}

# 获取本机主IP地址
get_primary_ip() {
    # 尝试多种方式获取主IP
    local ip

    # 方式1: 通过默认路由接口
    ip=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+')
    if validate_ip "$ip"; then
        echo "$ip"
        return 0
    fi

    # 方式2: 通过hostname -I
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    if validate_ip "$ip"; then
        echo "$ip"
        return 0
    fi

    # 方式3: 通过网络接口
    ip=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | head -n1 | awk '{print $2}' | cut -d/ -f1)
    if validate_ip "$ip"; then
        echo "$ip"
        return 0
    fi

    return 1
}

# 添加端口转发规则
add_forward_rule() {
    echo ""
    echo_info "添加端口转发规则"
    echo ""

    # 获取本机IP
    local local_ip
    local_ip=$(get_primary_ip)
    if [ -z "$local_ip" ]; then
        echo_error "无法获取本机IP地址"
        return 1
    fi
    echo_info "本机IP地址: $local_ip"
    echo ""

    # 输入源端口
    while true; do
        read -p "请输入源端口 (本机监听端口): " src_port
        if validate_port "$src_port"; then
            break
        else
            echo_error "无效的端口号，请输入1-65535之间的数字"
        fi
    done

    # 输入目标IP
    while true; do
        read -p "请输入目标IP地址: " dst_ip
        if validate_ip "$dst_ip"; then
            break
        else
            echo_error "无效的IP地址"
        fi
    done

    # 输入目标端口
    while true; do
        read -p "请输入目标端口: " dst_port
        if validate_port "$dst_port"; then
            break
        else
            echo_error "无效的端口号，请输入1-65535之间的数字"
        fi
    done

    # 选择协议
    echo ""
    echo "请选择协议:"
    echo "  1) TCP"
    echo "  2) UDP"
    echo "  3) TCP和UDP"
    read -p "请选择 (1-3): " proto_choice

    case $proto_choice in
        1) protocol="tcp" ;;
        2) protocol="udp" ;;
        3) protocol="both" ;;
        *)
            echo_error "无效选择，默认使用TCP"
            protocol="tcp"
            ;;
    esac

    # 输入备注
    read -p "请输入备注 (可选): " comment
    comment=${comment:-"Port forward rule"}

    echo ""
    echo_info "配置摘要:"
    echo "  源地址: $local_ip:$src_port"
    echo "  目标地址: $dst_ip:$dst_port"
    echo "  协议: $protocol"
    echo "  备注: $comment"
    echo ""

    read -p "确认添加? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy] ]]; then
        echo_warn "已取消"
        return 0
    fi

    # 启用IP转发
    enable_ip_forward

    # 添加iptables规则
    echo_info "添加iptables规则..."

    if [[ "$protocol" == "both" ]]; then
        # TCP规则
        iptables -t nat -A PREROUTING -p tcp --dport "$src_port" -j DNAT --to-destination "$dst_ip:$dst_port"
        iptables -t nat -A POSTROUTING -p tcp -d "$dst_ip" --dport "$dst_port" -j SNAT --to-source "$local_ip"

        # UDP规则
        iptables -t nat -A PREROUTING -p udp --dport "$src_port" -j DNAT --to-destination "$dst_ip:$dst_port"
        iptables -t nat -A POSTROUTING -p udp -d "$dst_ip" --dport "$dst_port" -j SNAT --to-source "$local_ip"

        # 保存到配置文件
        echo "tcp|$local_ip|$src_port|$dst_ip|$dst_port|$comment" >> "$CONFIG_FILE"
        echo "udp|$local_ip|$src_port|$dst_ip|$dst_port|$comment" >> "$CONFIG_FILE"
    else
        iptables -t nat -A PREROUTING -p "$protocol" --dport "$src_port" -j DNAT --to-destination "$dst_ip:$dst_port"
        iptables -t nat -A POSTROUTING -p "$protocol" -d "$dst_ip" --dport "$dst_port" -j SNAT --to-source "$local_ip"

        # 保存到配置文件
        echo "$protocol|$local_ip|$src_port|$dst_ip|$dst_port|$comment" >> "$CONFIG_FILE"
    fi

    # 保存iptables规则
    save_iptables

    echo ""
    echo_success "端口转发规则已添加"
    echo_info "转发规则: $local_ip:$src_port -> $dst_ip:$dst_port ($protocol)"
}

# 列出所有转发规则
list_forward_rules() {
    echo ""
    echo_info "当前端口转发规则"
    echo ""

    # 调试信息
    echo_info "配置文件路径: $CONFIG_FILE"
    if [ -f "$CONFIG_FILE" ]; then
        local line_count=$(wc -l < "$CONFIG_FILE" 2>/dev/null || echo "0")
        echo_info "配置文件行数: $line_count"
    else
        echo_warn "配置文件不存在"
    fi
    echo ""

    if [ ! -f "$CONFIG_FILE" ] || [ ! -s "$CONFIG_FILE" ]; then
        echo_warn "配置文件中暂无转发规则"
        echo ""
        # 即使配置文件为空，也显示iptables中的规则
        echo_info "检查iptables中的NAT规则:"
        echo ""
        iptables -t nat -L PREROUTING -n -v --line-numbers | grep DNAT || echo_warn "iptables中无DNAT规则"
        return 0
    fi

    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
    printf "${CYAN}║${NC} ${YELLOW}%-3s${NC} ${YELLOW}%-8s${NC} ${YELLOW}%-15s${NC} ${YELLOW}%-6s${NC} ${YELLOW}%-15s${NC} ${YELLOW}%-6s${NC} ${YELLOW}%-15s${NC} ${CYAN}║${NC}\n" \
        "No" "协议" "源IP" "源端口" "目标IP" "目标端口" "备注"
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════════════════════╣${NC}"

    local index=1
    while IFS='|' read -r protocol src_ip src_port dst_ip dst_port comment; do
        # 跳过空行
        [ -z "$protocol" ] && continue

        # 截断过长的备注
        if [ ${#comment} -gt 15 ]; then
            comment="${comment:0:12}..."
        fi

        printf "${CYAN}║${NC} %-3s %-8s %-15s %-6s %-15s %-6s %-15s ${CYAN}║${NC}\n" \
            "$index" "$protocol" "$src_ip" "$src_port" "$dst_ip" "$dst_port" "$comment"

        ((index++))
    done < "$CONFIG_FILE"

    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # 显示活跃的iptables NAT规则
    echo_info "活跃的iptables NAT规则:"
    echo ""
    iptables -t nat -L PREROUTING -n -v --line-numbers | grep DNAT || echo_warn "无DNAT规则"
}

# 删除转发规则
delete_forward_rule() {
    echo ""

    if [ ! -f "$CONFIG_FILE" ] || [ ! -s "$CONFIG_FILE" ]; then
        echo_warn "暂无转发规则可删除"
        return 0
    fi

    # 显示规则列表
    list_forward_rules

    # 统计规则数量
    local total_rules
    total_rules=$(grep -c . "$CONFIG_FILE" 2>/dev/null || echo "0")

    if [ "$total_rules" -eq 0 ]; then
        echo_warn "暂无转发规则可删除"
        return 0
    fi

    echo_info "请输入要删除的规则编号 (1-$total_rules)"
    read -p "规则编号: " rule_num

    if ! [[ "$rule_num" =~ ^[0-9]+$ ]] || [ "$rule_num" -lt 1 ] || [ "$rule_num" -gt "$total_rules" ]; then
        echo_error "无效的规则编号"
        return 1
    fi

    # 获取规则信息
    local rule_line
    rule_line=$(sed -n "${rule_num}p" "$CONFIG_FILE")

    IFS='|' read -r protocol src_ip src_port dst_ip dst_port comment <<< "$rule_line"

    echo ""
    echo_info "将删除以下规则:"
    echo "  协议: $protocol"
    echo "  源地址: $src_ip:$src_port"
    echo "  目标地址: $dst_ip:$dst_port"
    echo "  备注: $comment"
    echo ""

    read -p "确认删除? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy] ]]; then
        echo_warn "已取消"
        return 0
    fi

    # 删除iptables规则
    echo_info "删除iptables规则..."

    # 删除PREROUTING规则
    iptables -t nat -D PREROUTING -p "$protocol" --dport "$src_port" -j DNAT --to-destination "$dst_ip:$dst_port" 2>/dev/null || \
        echo_warn "PREROUTING规则可能已不存在"

    # 删除POSTROUTING规则
    iptables -t nat -D POSTROUTING -p "$protocol" -d "$dst_ip" --dport "$dst_port" -j SNAT --to-source "$src_ip" 2>/dev/null || \
        echo_warn "POSTROUTING规则可能已不存在"

    # 从配置文件删除
    sed -i "${rule_num}d" "$CONFIG_FILE"

    # 保存iptables规则
    save_iptables

    echo ""
    echo_success "规则已删除"
}

# 清空所有转发规则
clear_all_rules() {
    echo ""
    echo_warn "⚠️  警告: 此操作将删除配置文件中记录的所有端口转发规则"
    echo_info "只会删除由本脚本管理的规则,不会影响其他iptables规则"
    echo ""

    if [ ! -f "$CONFIG_FILE" ] || [ ! -s "$CONFIG_FILE" ]; then
        echo_warn "配置文件中没有规则需要清空"
        return 0
    fi

    # 显示将要删除的规则
    echo_info "将删除以下规则:"
    echo ""

    local index=1
    while IFS='|' read -r protocol src_ip src_port dst_ip dst_port comment; do
        [ -z "$protocol" ] && continue
        echo "  $index. $protocol $src_ip:$src_port -> $dst_ip:$dst_port"
        ((index++))
    done < "$CONFIG_FILE"

    echo ""
    read -p "确认清空所有规则? (输入 'yes' 确认): " confirm
    if [ "$confirm" != "yes" ]; then
        echo_warn "已取消"
        return 0
    fi

    echo_info "删除iptables规则..."

    # 逐条删除iptables规则
    local count=0
    while IFS='|' read -r protocol src_ip src_port dst_ip dst_port comment; do
        [ -z "$protocol" ] && continue

        # 删除PREROUTING规则
        iptables -t nat -D PREROUTING -p "$protocol" --dport "$src_port" -j DNAT --to-destination "$dst_ip:$dst_port" 2>/dev/null && \
            echo_info "已删除 DNAT: $protocol $src_ip:$src_port -> $dst_ip:$dst_port" || \
            echo_warn "DNAT规则可能已不存在: $protocol $src_ip:$src_port"

        # 删除POSTROUTING规则
        iptables -t nat -D POSTROUTING -p "$protocol" -d "$dst_ip" --dport "$dst_port" -j SNAT --to-source "$src_ip" 2>/dev/null && \
            echo_info "已删除 SNAT: $protocol -> $dst_ip:$dst_port" || \
            echo_warn "SNAT规则可能已不存在: $protocol -> $dst_ip:$dst_port"

        ((count++))
    done < "$CONFIG_FILE"

    # 清空配置文件
    > "$CONFIG_FILE"

    # 保存iptables规则
    save_iptables

    echo ""
    echo_success "已删除 $count 条转发规则"
}

# 保存iptables规则
save_iptables() {
    echo_info "保存iptables规则..."

    if command -v iptables-save >/dev/null 2>&1; then
        if command -v netfilter-persistent >/dev/null 2>&1; then
            netfilter-persistent save
        elif [ -d "/etc/iptables" ]; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        elif command -v service >/dev/null 2>&1; then
            service iptables save 2>/dev/null || true
        fi
        echo_success "iptables规则已保存"
    else
        echo_warn "无法自动保存iptables规则，请手动保存"
    fi
}

# 恢复保存的转发规则
restore_rules() {
    echo_info "恢复保存的端口转发规则..."

    if [ ! -f "$CONFIG_FILE" ] || [ ! -s "$CONFIG_FILE" ]; then
        echo_warn "没有保存的规则需要恢复"
        return 0
    fi

    # 启用IP转发
    enable_ip_forward

    local count=0
    while IFS='|' read -r protocol src_ip src_port dst_ip dst_port comment; do
        # 跳过空行
        [ -z "$protocol" ] && continue

        # 添加iptables规则
        iptables -t nat -A PREROUTING -p "$protocol" --dport "$src_port" -j DNAT --to-destination "$dst_ip:$dst_port" 2>/dev/null || true
        iptables -t nat -A POSTROUTING -p "$protocol" -d "$dst_ip" --dport "$dst_port" -j SNAT --to-source "$src_ip" 2>/dev/null || true

        ((count++))
    done < "$CONFIG_FILE"

    echo_success "已恢复 $count 条转发规则"
}

# 从iptables导入现有规则
import_from_iptables() {
    echo ""
    echo_info "从iptables导入现有的端口转发规则"
    echo ""

    # 获取本机IP
    local local_ip
    local_ip=$(get_primary_ip)
    if [ -z "$local_ip" ]; then
        echo_error "无法获取本机IP地址"
        return 1
    fi

    # 获取所有DNAT规则
    local rules
    rules=$(iptables -t nat -L PREROUTING -n --line-numbers | grep DNAT)

    if [ -z "$rules" ]; then
        echo_warn "iptables中没有发现DNAT规则"
        return 0
    fi

    echo_info "发现以下DNAT规则:"
    echo ""
    echo "$rules"
    echo ""

    read -p "是否导入这些规则到配置文件? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy] ]]; then
        echo_warn "已取消导入"
        return 0
    fi

    # 解析并导入规则
    local count=0
    while read -r line; do
        # 跳过标题行
        [[ "$line" =~ ^num ]] && continue
        [[ "$line" =~ ^Chain ]] && continue
        [ -z "$line" ] && continue

        # 提取协议、端口和目标
        local protocol=$(echo "$line" | awk '{print $4}')
        local dport=$(echo "$line" | awk '{print $7}' | sed 's/dpt://')
        local to_dest=$(echo "$line" | awk '{print $NF}' | sed 's/to://')

        # 分离目标IP和端口
        local dst_ip="${to_dest%:*}"
        local dst_port="${to_dest#*:}"

        # 验证数据
        if validate_ip "$dst_ip" && validate_port "$dport" && validate_port "$dst_port"; then
            # 检查是否已存在
            if ! grep -q "^${protocol}|.*|${dport}|${dst_ip}|${dst_port}|" "$CONFIG_FILE" 2>/dev/null; then
                echo "${protocol}|${local_ip}|${dport}|${dst_ip}|${dst_port}|Imported from iptables" >> "$CONFIG_FILE"
                echo_success "已导入: ${protocol} ${local_ip}:${dport} -> ${dst_ip}:${dst_port}"
                ((count++))
            else
                echo_info "跳过重复规则: ${protocol} ${local_ip}:${dport} -> ${dst_ip}:${dst_port}"
            fi
        fi
    done <<< "$rules"

    echo ""
    echo_success "成功导入 $count 条规则"
}

# 显示菜单
show_menu() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}      ${YELLOW}端口转发管理${NC}              ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BLUE}1.${NC} 添加转发规则"
    echo -e "  ${BLUE}2.${NC} 列出转发规则"
    echo -e "  ${BLUE}3.${NC} 删除转发规则"
    echo -e "  ${BLUE}4.${NC} 清空所有规则"
    echo -e "  ${BLUE}5.${NC} 恢复保存的规则"
    echo -e "  ${BLUE}6.${NC} 从iptables导入规则"
    echo -e "  ${RED}0.${NC} 返回主菜单"
    echo ""
}

# 主函数
main() {
    check_root
    check_requirements

    while true; do
        show_menu
        read -p "请选择 (0-6): " choice

        case $choice in
            1)
                add_forward_rule
                ;;
            2)
                list_forward_rules
                ;;
            3)
                delete_forward_rule
                ;;
            4)
                clear_all_rules
                ;;
            5)
                restore_rules
                ;;
            6)
                import_from_iptables
                ;;
            0)
                echo ""
                echo_info "返回主菜单"
                exit 0
                ;;
            *)
                echo_error "无效选项"
                ;;
        esac

        echo ""
        echo -e "${CYAN}按任意键继续...${NC}"
        read -n 1
    done
}

main "$@"
