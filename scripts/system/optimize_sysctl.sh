#!/bin/bash

# Sysctl 系统参数优化脚本
# 优化 TCP 缓冲区、开启 TCP Fast Open、网络性能调优等
# 适用于所有类型服务器（建站、代理等）

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# 日志函数
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
    log_error "此脚本需要 root 权限运行"
    echo "请使用: sudo $0"
    exit 1
fi

# 分隔线
print_separator() {
    echo -e "${CYAN}────────────────────────────────────────────────────${NC}"
}

# 获取当前参数值（如果存在）
get_current_value() {
    local key="$1"
    sysctl -n "$key" 2>/dev/null | tr -s ' \t' ' ' | sed 's/^ //;s/ $//' || echo "(未设置)"
}

# ============================================================
# 定义优化参数
# ============================================================

# 参数格式: "sysctl键=推荐值|说明"
OPTIMIZE_PARAMS=(
    # TCP 缓冲区优化
    "net.core.rmem_max=16777216|TCP 最大接收缓冲区 (16MB)"
    "net.core.wmem_max=16777216|TCP 最大发送缓冲区 (16MB)"
    "net.core.rmem_default=1048576|TCP 默认接收缓冲区 (1MB)"
    "net.core.wmem_default=1048576|TCP 默认发送缓冲区 (1MB)"
    "net.ipv4.tcp_rmem=4096 87380 16777216|TCP 接收缓冲区范围 (最小/默认/最大)"
    "net.ipv4.tcp_wmem=4096 65536 16777216|TCP 发送缓冲区范围 (最小/默认/最大)"

    # TCP Fast Open
    "net.ipv4.tcp_fastopen=3|TCP Fast Open (3=客户端+服务端都启用)"

    # 连接优化
    "net.core.somaxconn=65535|Socket 最大连接队列"
    "net.core.netdev_max_backlog=65535|网络设备接收队列最大长度"
    "net.ipv4.tcp_max_syn_backlog=65535|SYN 队列最大长度"
    "net.ipv4.tcp_max_tw_buckets=2000000|TIME_WAIT 状态最大数量"
    "net.ipv4.tcp_tw_reuse=1|允许复用 TIME_WAIT 连接"
    "net.ipv4.tcp_fin_timeout=10|FIN_WAIT2 超时时间 (秒)"

    # Keepalive 优化
    "net.ipv4.tcp_keepalive_time=600|Keepalive 探测间隔 (秒)"
    "net.ipv4.tcp_keepalive_intvl=30|Keepalive 探测重试间隔 (秒)"
    "net.ipv4.tcp_keepalive_probes=10|Keepalive 探测最大次数"

    # 其他网络优化
    "net.ipv4.tcp_mtu_probing=1|启用 TCP MTU 探测"
    "net.ipv4.tcp_syncookies=1|启用 SYN Cookie 防护"
    "net.core.default_qdisc=fq|默认队列调度算法 (fq 配合 BBR)"
    "net.ipv4.tcp_congestion_control=bbr|TCP 拥塞控制算法 (BBR)"

    # 文件描述符
    "fs.file-max=1000000|系统最大文件描述符数"

    # 内存优化
    "vm.swappiness=10|Swap 使用倾向 (越低越倾向使用物理内存)"
    "net.ipv4.tcp_slow_start_after_idle=0|关闭空闲后慢启动 (保持长连接性能)"
)

# ============================================================
# 第一步：检测当前配置
# ============================================================

echo
echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${BOLD}          Sysctl 系统参数优化工具                     ${CYAN}║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
echo

log_info "正在检测当前系统参数配置..."
echo

# 需要优化的参数列表
NEED_OPTIMIZE=()
ALREADY_OPTIMAL=()

printf "  ${BOLD}%-45s %-20s %-20s${NC}\n" "参数" "当前值" "推荐值"
print_separator

for param_entry in "${OPTIMIZE_PARAMS[@]}"; do
    # 解析参数
    local_kv="${param_entry%%|*}"
    local_desc="${param_entry##*|}"
    local_key="${local_kv%%=*}"
    local_recommended="${local_kv#*=}"

    # 获取当前值
    current_value=$(get_current_value "$local_key")

    # 比较当前值与推荐值
    if [ "$current_value" = "$local_recommended" ]; then
        printf "  ${GREEN}%-45s${NC} %-20s %-20s ${GREEN}[OK]${NC}\n" "$local_key" "$current_value" "$local_recommended"
        ALREADY_OPTIMAL+=("$param_entry")
    else
        printf "  ${YELLOW}%-45s${NC} %-20s %-20s ${YELLOW}[需优化]${NC}\n" "$local_key" "$current_value" "$local_recommended"
        NEED_OPTIMIZE+=("$param_entry")
    fi
done

echo
print_separator

# 统计结果
total=${#OPTIMIZE_PARAMS[@]}
optimal=${#ALREADY_OPTIMAL[@]}
need_optimize=${#NEED_OPTIMIZE[@]}

echo
log_info "检测完成: 共 ${total} 项参数, ${GREEN}${optimal} 项已最优${NC}, ${YELLOW}${need_optimize} 项可优化${NC}"

# 如果全部已最优
if [ ${need_optimize} -eq 0 ]; then
    echo
    log_success "所有参数已处于最优状态，无需修改!"
    exit 0
fi

# ============================================================
# 第二步：询问用户是否执行优化
# ============================================================

echo
echo -e "${YELLOW}以下参数将被优化:${NC}"
echo
for param_entry in "${NEED_OPTIMIZE[@]}"; do
    local_kv="${param_entry%%|*}"
    local_desc="${param_entry##*|}"
    local_key="${local_kv%%=*}"
    local_recommended="${local_kv#*=}"
    echo -e "  ${CYAN}${local_key}${NC} = ${GREEN}${local_recommended}${NC}"
    echo -e "    ${local_desc}"
done

echo
echo -e "${YELLOW}注意事项:${NC}"
echo -e "  - 修改前会自动备份原始 /etc/sysctl.conf"
echo -e "  - 优化参数写入 /etc/sysctl.d/99-uls-optimize.conf (不污染原配置)"
echo -e "  - 重启后参数依然生效"
echo -e "  - 可随时通过删除配置文件还原"
echo

read -p "是否执行优化? (y/N): " confirm

if [[ ! $confirm =~ ^[Yy] ]]; then
    log_info "已取消操作"
    exit 0
fi

# ============================================================
# 第三步：执行优化
# ============================================================

echo
log_info "开始优化系统参数..."

# 备份原始 sysctl.conf
BACKUP_FILE="/etc/sysctl.conf.bak.$(date +%Y%m%d_%H%M%S)"
cp /etc/sysctl.conf "$BACKUP_FILE"
log_info "已备份原始配置到 ${BACKUP_FILE}"

# 写入优化参数到独立配置文件
CONF_FILE="/etc/sysctl.d/99-uls-optimize.conf"

{
    echo "# ULS Sysctl 系统参数优化配置"
    echo "# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "# 由 ULS (Useful Linux Scripts) 生成"
    echo "# 删除此文件并执行 sysctl --system 即可还原"
    echo ""
} > "$CONF_FILE"

for param_entry in "${NEED_OPTIMIZE[@]}"; do
    local_kv="${param_entry%%|*}"
    local_desc="${param_entry##*|}"
    local_key="${local_kv%%=*}"
    local_recommended="${local_kv#*=}"

    echo "# ${local_desc}" >> "$CONF_FILE"
    echo "${local_key} = ${local_recommended}" >> "$CONF_FILE"
    echo "" >> "$CONF_FILE"
done

log_info "优化配置已写入 ${CONF_FILE}"

# 应用配置
log_info "正在应用配置..."
if sysctl --system > /dev/null 2>&1; then
    log_success "配置已成功应用!"
else
    log_warn "部分参数应用可能失败，请检查系统日志"
fi

# ============================================================
# 第四步：验证结果
# ============================================================

echo
log_info "正在验证优化结果..."
echo

VERIFY_OK=0
VERIFY_FAIL=0

for param_entry in "${NEED_OPTIMIZE[@]}"; do
    local_kv="${param_entry%%|*}"
    local_key="${local_kv%%=*}"
    local_recommended="${local_kv#*=}"

    current_value=$(get_current_value "$local_key")
    if [ "$current_value" = "$local_recommended" ]; then
        echo -e "  ${GREEN}[OK]${NC} ${local_key} = ${current_value}"
        VERIFY_OK=$((VERIFY_OK + 1))
    else
        echo -e "  ${RED}[FAIL]${NC} ${local_key}: 期望 ${local_recommended}, 实际 ${current_value}"
        VERIFY_FAIL=$((VERIFY_FAIL + 1))
    fi
done

echo
print_separator
echo
if [ $VERIFY_FAIL -eq 0 ]; then
    log_success "所有 ${VERIFY_OK} 项参数优化成功!"
else
    log_warn "${VERIFY_OK} 项成功, ${VERIFY_FAIL} 项未能生效 (可能需要重启或内核不支持)"
fi

echo
echo -e "${CYAN}还原方法:${NC}"
echo -e "  sudo rm ${CONF_FILE} && sudo sysctl --system"
echo
