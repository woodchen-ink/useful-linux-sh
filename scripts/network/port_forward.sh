#!/bin/bash

# 端口转发管理脚本
# iptables: 内核 DNAT + MASQUERADE 转发, 目标看到的来源是本机 IP
# realm:    用户态程序转发, 可通过 PROXY protocol 把访客 IP 传给目标

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

# realm 配置
# 规则以 REALM_RULES_FILE 为准, config.toml 每次由规则文件整体生成, 不要手改
# 规则格式: 监听端口|目标主机|目标端口|协议(tcp/both)|PROXY版本(0=关闭/1/2)|备注
REALM_VERSION="2.9.6"
REALM_BINARY="/usr/local/bin/realm"
REALM_CONFIG_DIR="/etc/realm"
REALM_CONFIG_FILE="${REALM_CONFIG_DIR}/config.toml"
REALM_SERVICE_FILE="/etc/systemd/system/realm.service"
REALM_RULES_FILE="/etc/uls/realm_forward.conf"

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
    touch "$REALM_RULES_FILE"
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
        if ! validate_port "$src_port"; then
            echo_error "无效的端口号，请输入1-65535之间的数字"
        elif realm_rule_uses_port "$src_port"; then
            # DNAT 在 PREROUTING 先于本机程序生效, 会把 realm 的流量截走
            echo_error "端口 $src_port 已被 realm 转发规则占用"
        else
            break
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

    # 检查UFW是否运行
    local ufw_active=false
    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        ufw_active=true
        echo_info "检测到UFW防火墙已启用"
    fi

    if [[ "$protocol" == "both" ]]; then
        # TCP规则 - PREROUTING用于外部流量，使用MASQUERADE自动选择源IP
        iptables -t nat -A PREROUTING -p tcp --dport "$src_port" -j DNAT --to-destination "$dst_ip:$dst_port"
        iptables -t nat -A POSTROUTING -p tcp -d "$dst_ip" --dport "$dst_port" -j MASQUERADE

        # UDP规则
        iptables -t nat -A PREROUTING -p udp --dport "$src_port" -j DNAT --to-destination "$dst_ip:$dst_port"
        iptables -t nat -A POSTROUTING -p udp -d "$dst_ip" --dport "$dst_port" -j MASQUERADE

        # 添加FORWARD规则允许转发流量（解决UFW阻止问题）
        iptables -A FORWARD -p tcp -d "$dst_ip" --dport "$dst_port" -j ACCEPT
        iptables -A FORWARD -p udp -d "$dst_ip" --dport "$dst_port" -j ACCEPT

        # 保存到配置文件
        echo "tcp|$local_ip|$src_port|$dst_ip|$dst_port|$comment" >> "$CONFIG_FILE"
        echo "udp|$local_ip|$src_port|$dst_ip|$dst_port|$comment" >> "$CONFIG_FILE"
    else
        iptables -t nat -A PREROUTING -p "$protocol" --dport "$src_port" -j DNAT --to-destination "$dst_ip:$dst_port"
        iptables -t nat -A POSTROUTING -p "$protocol" -d "$dst_ip" --dport "$dst_port" -j MASQUERADE

        # 添加FORWARD规则允许转发流量
        iptables -A FORWARD -p "$protocol" -d "$dst_ip" --dport "$dst_port" -j ACCEPT

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

    # 删除POSTROUTING规则 - 尝试删除MASQUERADE规则（新格式）
    iptables -t nat -D POSTROUTING -p "$protocol" -d "$dst_ip" --dport "$dst_port" -j MASQUERADE 2>/dev/null || \
        # 兼容旧的SNAT规则
        iptables -t nat -D POSTROUTING -p "$protocol" -d "$dst_ip" --dport "$dst_port" -j SNAT --to-source "$src_ip" 2>/dev/null || \
        echo_warn "POSTROUTING规则可能已不存在"

    # 删除FORWARD规则
    iptables -D FORWARD -p "$protocol" -d "$dst_ip" --dport "$dst_port" -j ACCEPT 2>/dev/null || \
        echo_warn "FORWARD规则可能已不存在"

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

        # 删除POSTROUTING规则 - 尝试新格式和旧格式
        iptables -t nat -D POSTROUTING -p "$protocol" -d "$dst_ip" --dport "$dst_port" -j MASQUERADE 2>/dev/null || \
            iptables -t nat -D POSTROUTING -p "$protocol" -d "$dst_ip" --dport "$dst_port" -j SNAT --to-source "$src_ip" 2>/dev/null || \
            echo_warn "POSTROUTING规则可能已不存在: $protocol -> $dst_ip:$dst_port"

        # 删除FORWARD规则
        iptables -D FORWARD -p "$protocol" -d "$dst_ip" --dport "$dst_port" -j ACCEPT 2>/dev/null || true

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

        # 添加iptables规则 - 使用MASQUERADE
        iptables -t nat -A PREROUTING -p "$protocol" --dport "$src_port" -j DNAT --to-destination "$dst_ip:$dst_port" 2>/dev/null || true
        iptables -t nat -A POSTROUTING -p "$protocol" -d "$dst_ip" --dport "$dst_port" -j MASQUERADE 2>/dev/null || true
        # 添加FORWARD规则
        iptables -A FORWARD -p "$protocol" -d "$dst_ip" --dport "$dst_port" -j ACCEPT 2>/dev/null || true

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

# ==================== realm 转发 ====================

# 验证目标主机: IPv4 / IPv6 / 域名
validate_host() {
    local host=$1
    local domain_regex='^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$'

    validate_ip "$host" && return 0
    [[ "$host" =~ $domain_regex ]] && return 0
    # IPv6 只做粗校验, 真正解析交给 realm
    [[ "$host" == *:* && "$host" =~ ^[0-9A-Fa-f:.]+$ ]] && return 0
    return 1
}

# realm remote 字段: IPv6 需要加方括号
format_remote() {
    local host=$1 port=$2
    if [[ "$host" == *:* ]]; then
        echo "[$host]:$port"
    else
        echo "$host:$port"
    fi
}

realm_rule_uses_port() {
    [ -f "$REALM_RULES_FILE" ] || return 1
    awk -F'|' -v p="$1" '$1 == p { found = 1 } END { exit !found }' "$REALM_RULES_FILE"
}

iptables_rule_uses_port() {
    [ -f "$CONFIG_FILE" ] || return 1
    awk -F'|' -v p="$1" '$3 == p { found = 1 } END { exit !found }' "$CONFIG_FILE"
}

port_is_listening() {
    ss -lntu 2>/dev/null | awk 'NR > 1 { print $5 }' | grep -qE "[:.]$1\$"
}

realm_rule_count() {
    grep -c . "$REALM_RULES_FILE" 2>/dev/null || true
}

realm_detect_arch() {
    case "$(uname -m)" in
        x86_64) echo "x86_64" ;;
        aarch64 | arm64) echo "aarch64" ;;
        *) return 1 ;;
    esac
}

# 安装 realm 二进制与 systemd 服务, 已安装则跳过
realm_install() {
    if [ -x "$REALM_BINARY" ] && [ -f "$REALM_SERVICE_FILE" ]; then
        return 0
    fi

    local arch
    if ! arch=$(realm_detect_arch); then
        echo_error "不支持的系统架构: $(uname -m) (仅支持 x86_64 / aarch64)"
        return 1
    fi

    if [ ! -x "$REALM_BINARY" ]; then
        echo_info "正在安装 realm v${REALM_VERSION} ($arch)..."

        # musl 版为静态编译, 不依赖系统 glibc 版本
        local url="https://github.com/zhboner/realm/releases/download/v${REALM_VERSION}/realm-${arch}-unknown-linux-musl.tar.gz"
        local tmp_dir
        tmp_dir=$(mktemp -d)

        if ! curl -fsSL --connect-timeout 15 "$url" -o "$tmp_dir/realm.tar.gz"; then
            echo_error "realm 下载失败, 请检查到 GitHub 的网络连接"
            rm -rf "$tmp_dir"
            return 1
        fi
        if ! tar -xzf "$tmp_dir/realm.tar.gz" -C "$tmp_dir" || [ ! -f "$tmp_dir/realm" ]; then
            echo_error "realm 解压失败, 下载内容可能不完整"
            rm -rf "$tmp_dir"
            return 1
        fi

        install -m 755 "$tmp_dir/realm" "$REALM_BINARY"
        rm -rf "$tmp_dir"

        if ! "$REALM_BINARY" --version >/dev/null 2>&1; then
            echo_error "realm 无法运行, 已删除"
            rm -f "$REALM_BINARY"
            return 1
        fi
        echo_success "realm 已安装: $("$REALM_BINARY" --version 2>&1 | head -n1)"
    fi

    mkdir -p "$REALM_CONFIG_DIR"
    cat > "$REALM_SERVICE_FILE" <<EOF
[Unit]
Description=realm port forwarding (managed by ULS)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$REALM_BINARY -c $REALM_CONFIG_FILE
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
}

# 由规则文件整体生成 config.toml
realm_render_config() {
    local tmp_file="${REALM_CONFIG_FILE}.tmp"

    {
        echo "# 由 ULS port_forward.sh 生成, 请通过脚本菜单修改, 手动修改会被覆盖"
        echo ""
        echo "[log]"
        echo 'level = "warn"'
        echo 'output = "stdout"'
        echo ""
        echo "[network]"
        echo "no_tcp = false"
        echo "use_udp = false"

        local listen_port host port proto proxy comment
        while IFS='|' read -r listen_port host port proto proxy comment; do
            [ -z "$listen_port" ] && continue

            local net_opts=()
            [ "$proto" == "both" ] && net_opts+=("use_udp = true")
            if [ "$proxy" == "1" ] || [ "$proxy" == "2" ]; then
                net_opts+=("send_proxy = true" "send_proxy_version = $proxy")
            fi

            echo ""
            echo "# $comment"
            echo "[[endpoints]]"
            echo "listen = \"0.0.0.0:$listen_port\""
            echo "remote = \"$(format_remote "$host" "$port")\""
            if [ ${#net_opts[@]} -gt 0 ]; then
                local joined
                joined=$(printf ', %s' "${net_opts[@]}")
                echo "network = { ${joined:2} }"
            fi
        done < "$REALM_RULES_FILE"
    } > "$tmp_file"

    mv -f "$tmp_file" "$REALM_CONFIG_FILE"
}

# 按规则文件生成配置并重启服务; 无规则时停止服务
realm_apply() {
    if [ "$(realm_rule_count)" -eq 0 ]; then
        realm_render_config
        if systemctl is-active --quiet realm 2>/dev/null; then
            systemctl stop realm
        fi
        systemctl disable realm >/dev/null 2>&1 || true
        echo_info "已无 realm 规则, realm 服务已停止"
        return 0
    fi

    realm_render_config
    systemctl enable realm >/dev/null 2>&1
    systemctl restart realm

    # 配置错误时 realm 会在启动后立即退出, 稍等再判断
    sleep 2
    if ! systemctl is-active --quiet realm; then
        echo_error "realm 启动失败, 最近日志:"
        journalctl -u realm -n 15 --no-pager 2>/dev/null || true
        return 1
    fi
    echo_success "realm 服务已重启"
}

# 打印目标端接收 PROXY protocol 的配置提示
print_proxy_protocol_hint() {
    local listen_port=$1 proxy=$2
    local local_ip
    local_ip=$(get_primary_ip || echo "<本机IP>")

    echo ""
    echo_warn "已开启 PROXY protocol v$proxy, 目标端口必须能解析 PROXY 头, 否则连接会失败"
    echo_info "目标端为 nginx 时的配置示例:"
    echo ""
    echo -e "${CYAN}    server {${NC}"
    echo -e "${CYAN}        listen <目标端口> ssl proxy_protocol;${NC}"
    echo -e "${CYAN}        set_real_ip_from $local_ip;   # 只信任本中转机${NC}"
    echo -e "${CYAN}        real_ip_header proxy_protocol;${NC}"
    echo -e "${CYAN}        ...${NC}"
    echo -e "${CYAN}    }${NC}"
    echo ""
    echo_info "Xray / V2Ray 入站: 在 streamSettings.sockopt 中设置 \"acceptProxyProtocol\": true"
    echo_info "加了 proxy_protocol 的端口不能再被直接访问, 需要直连时请给转发单独开一个端口"
}

realm_add_rule() {
    echo ""
    echo_info "添加 realm 转发规则"
    echo ""

    local listen_port host port proto proxy comment

    while true; do
        read -p "请输入本机监听端口: " listen_port
        if ! validate_port "$listen_port"; then
            echo_error "无效的端口号，请输入1-65535之间的数字"
        elif realm_rule_uses_port "$listen_port"; then
            echo_error "端口 $listen_port 已有 realm 转发规则"
        elif iptables_rule_uses_port "$listen_port"; then
            echo_error "端口 $listen_port 已被 iptables 转发规则占用, 请先删除该规则"
        elif port_is_listening "$listen_port"; then
            echo_error "端口 $listen_port 已有程序在监听"
        else
            break
        fi
    done

    while true; do
        read -p "请输入目标地址 (IP 或域名): " host
        # 去掉用户可能带上的 IPv6 方括号
        host=${host#[}
        host=${host%]}
        if validate_host "$host"; then
            break
        fi
        echo_error "无效的目标地址"
    done

    while true; do
        read -p "请输入目标端口: " port
        if validate_port "$port"; then
            break
        fi
        echo_error "无效的端口号，请输入1-65535之间的数字"
    done

    echo ""
    echo "请选择协议:"
    echo "  1) TCP (网站选这个)"
    echo "  2) TCP和UDP"
    read -p "请选择 (1-2, 默认1): " proto_choice
    case $proto_choice in
        2) proto="both" ;;
        *) proto="tcp" ;;
    esac

    echo ""
    echo "是否通过 PROXY protocol 传递访客真实 IP?"
    echo "  0) 不传递 (目标看到本机 IP, 目标端无需改动)"
    echo "  1) PROXY protocol v1"
    echo "  2) PROXY protocol v2 (推荐, nginx / haproxy / Xray 均支持)"
    read -p "请选择 (0-2, 默认0): " proxy
    case $proxy in
        1 | 2) ;;
        *) proxy="0" ;;
    esac
    if [ "$proxy" != "0" ] && [ "$proto" == "both" ]; then
        echo_warn "PROXY protocol 只作用于 TCP, UDP 流量不会携带访客 IP"
    fi

    read -p "请输入备注 (可选): " comment
    # 备注写入以 | 分隔的规则文件, 不能含分隔符
    comment=${comment//|/ }
    comment=${comment:-"realm forward"}

    local proxy_text="关闭"
    [ "$proxy" != "0" ] && proxy_text="v$proxy"

    echo ""
    echo_info "配置摘要:"
    echo "  监听: 0.0.0.0:$listen_port"
    echo "  目标: $(format_remote "$host" "$port")"
    echo "  协议: $proto"
    echo "  PROXY protocol: $proxy_text"
    echo "  备注: $comment"
    echo ""

    read -p "确认添加? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy] ]]; then
        echo_warn "已取消"
        return 0
    fi

    realm_install || return 1

    echo "$listen_port|$host|$port|$proto|$proxy|$comment" >> "$REALM_RULES_FILE"

    if ! realm_apply; then
        # 回滚刚加入的规则, 避免一条坏规则拖垮其他转发
        echo_warn "正在回滚该规则..."
        sed -i '$d' "$REALM_RULES_FILE"
        realm_apply || true
        return 1
    fi

    echo ""
    echo_success "realm 转发已添加: 0.0.0.0:$listen_port -> $(format_remote "$host" "$port") ($proto)"

    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
        echo_warn "检测到 UFW 已启用, realm 是本机监听, 需放行端口: ufw allow $listen_port"
    fi

    [ "$proxy" != "0" ] && print_proxy_protocol_hint "$listen_port" "$proxy"
    return 0
}

realm_list_rules() {
    echo ""
    echo_info "realm 转发规则"
    echo ""

    if [ "$(realm_rule_count)" -eq 0 ]; then
        echo_warn "暂无 realm 转发规则"
        return 0
    fi

    printf "${YELLOW}%-4s %-8s %-30s %-6s %-7s %s${NC}\n" "No" "监听" "目标" "协议" "PROXY" "备注"
    echo "--------------------------------------------------------------------------------"

    local index=1
    local listen_port host port proto proxy comment
    while IFS='|' read -r listen_port host port proto proxy comment; do
        [ -z "$listen_port" ] && continue
        local proxy_text="-"
        [ "$proxy" == "1" ] || [ "$proxy" == "2" ] && proxy_text="v$proxy"
        printf "%-4s %-8s %-30s %-6s %-7s %s\n" \
            "$index" "$listen_port" "$(format_remote "$host" "$port")" "$proto" "$proxy_text" "$comment"
        index=$((index + 1))
    done < "$REALM_RULES_FILE"

    echo ""
    if systemctl is-active --quiet realm 2>/dev/null; then
        echo_info "realm 服务: ${GREEN}运行中${NC}"
    else
        echo_warn "realm 服务: 未运行 (可在菜单中查看服务状态)"
    fi
}

realm_delete_rule() {
    local total
    total=$(realm_rule_count)
    if [ "$total" -eq 0 ]; then
        echo ""
        echo_warn "暂无 realm 转发规则可删除"
        return 0
    fi

    realm_list_rules
    echo ""
    read -p "请输入要删除的规则编号 (1-$total): " rule_num

    if ! [[ "$rule_num" =~ ^[0-9]+$ ]] || [ "$rule_num" -lt 1 ] || [ "$rule_num" -gt "$total" ]; then
        echo_error "无效的规则编号"
        return 1
    fi

    # 规则文件可能含空行, 按非空行序号定位真实行号
    local line_no
    line_no=$(grep -n . "$REALM_RULES_FILE" | sed -n "${rule_num}p" | cut -d: -f1)

    local listen_port host port proto proxy comment
    IFS='|' read -r listen_port host port proto proxy comment < <(sed -n "${line_no}p" "$REALM_RULES_FILE")

    echo ""
    echo_info "将删除: 0.0.0.0:$listen_port -> $(format_remote "$host" "$port") ($proto) $comment"
    read -p "确认删除? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy] ]]; then
        echo_warn "已取消"
        return 0
    fi

    sed -i "${line_no}d" "$REALM_RULES_FILE"
    realm_apply
    echo_success "规则已删除"
}

realm_show_status() {
    echo ""
    if [ ! -x "$REALM_BINARY" ]; then
        echo_warn "realm 未安装, 添加第一条 realm 转发时会自动安装"
        return 0
    fi

    echo_info "版本: $("$REALM_BINARY" --version 2>&1 | head -n1)"
    echo_info "规则数: $(realm_rule_count)"
    echo_info "配置文件: $REALM_CONFIG_FILE"
    echo ""
    systemctl status realm --no-pager -l 2>/dev/null | head -n 15 || true
    echo ""
    echo_info "最近日志:"
    journalctl -u realm -n 10 --no-pager 2>/dev/null || true
}

realm_uninstall() {
    echo ""
    if [ ! -x "$REALM_BINARY" ] && [ ! -f "$REALM_SERVICE_FILE" ]; then
        echo_warn "realm 未安装"
        return 0
    fi

    echo_warn "将停止 realm 服务, 删除程序、服务与全部 $(realm_rule_count) 条 realm 转发规则"
    read -p "确认卸载? (输入 'yes' 确认): " confirm
    if [ "$confirm" != "yes" ]; then
        echo_warn "已取消"
        return 0
    fi

    systemctl stop realm 2>/dev/null || true
    systemctl disable realm >/dev/null 2>&1 || true
    rm -f "$REALM_SERVICE_FILE" "$REALM_BINARY"
    rm -rf "$REALM_CONFIG_DIR"
    : > "$REALM_RULES_FILE"
    systemctl daemon-reload

    echo_success "realm 已卸载"
}

# 显示菜单
show_menu() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}      ${YELLOW}端口转发管理${NC}              ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${YELLOW}[iptables 内核转发]${NC} 开销最低, 目标看到的来源是本机 IP"
    echo -e "  ${BLUE}1.${NC} 添加转发规则"
    echo -e "  ${BLUE}2.${NC} 列出转发规则"
    echo -e "  ${BLUE}3.${NC} 删除转发规则"
    echo -e "  ${BLUE}4.${NC} 清空所有规则"
    echo -e "  ${BLUE}5.${NC} 恢复保存的规则"
    echo -e "  ${BLUE}6.${NC} 从iptables导入规则"
    echo ""
    echo -e "  ${YELLOW}[realm 程序转发]${NC} 支持域名目标, 可通过 PROXY protocol 传递访客 IP"
    echo -e "  ${BLUE}7.${NC} 添加 realm 转发"
    echo -e "  ${BLUE}8.${NC} 列出 realm 转发"
    echo -e "  ${BLUE}9.${NC} 删除 realm 转发"
    echo -e "  ${BLUE}10.${NC} realm 服务状态"
    echo -e "  ${BLUE}11.${NC} 卸载 realm"
    echo ""
    echo -e "  ${RED}0.${NC} 返回主菜单"
    echo ""
}

# 主函数
main() {
    check_root
    check_requirements

    while true; do
        show_menu
        read -p "请选择 (0-11): " choice

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
            7)
                realm_add_rule || true
                ;;
            8)
                realm_list_rules
                ;;
            9)
                realm_delete_rule || true
                ;;
            10)
                realm_show_status
                ;;
            11)
                realm_uninstall
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
