#!/bin/bash

# 独服硬件配置与健康概览脚本
# 一站式查看 CPU / 内存 / 主板 / 硬盘 (含 SMART 寿命) / RAID / 网卡 (含协商速率) / 温度 / 电源
# 面向物理独立服务器;检测到虚拟化环境时会提示部分硬件信息不可用
# 全程只读:不修改任何系统配置,不写入除报告导出外的文件
# 依赖 dmidecode / smartmontools / pciutils / ethtool,缺失时提示并可选安装,未安装则降级展示
# 不使用 set -e:常驻菜单循环,单项采集失败不应退出整个工具,错误在各函数内显式处理

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m'

# 日志函数
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# 检查 root 权限:dmidecode / smartctl 均需 root
if [[ $EUID -ne 0 ]]; then
    log_error "此脚本需要 root 权限运行"
    echo "请使用: sudo $0"
    exit 1
fi

# 健康状态汇总:各模块检测到异常时追加一行,主菜单与体检报告统一展示
HEALTH_ISSUES=()

# 本次运行由脚本新装的包,退出时可选择移除;只记录装之前确实不存在的,不碰系统原有包
INSTALLED_PKGS=()

# 记录一条健康告警;参数1=级别(CRIT/WARN) 参数2=描述
add_issue() {
    HEALTH_ISSUES+=("$1|$2")
}

# ── 排版辅助 ──────────────────────────────────────────────────
# 统一版面宽度,所有框线/分隔线/表格按此对齐
LINE_WIDTH=64

# 重复字符;参数1=字符 参数2=次数
repeat_char() {
    local i out=""
    for ((i = 0; i < $2; i++)); do out="${out}$1"; done
    echo "$out"
}

# 细分隔线
print_line() {
    echo -e "${GRAY}$(repeat_char '─' $LINE_WIDTH)${NC}"
}

# 模块标题:上下双线包裹,左侧图标
print_section() {
    echo
    echo -e "${CYAN}┌$(repeat_char '─' $((LINE_WIDTH - 2)))┐${NC}"
    echo -e "${CYAN}│${NC} ${BOLD}$1${NC}"
    echo -e "${CYAN}└$(repeat_char '─' $((LINE_WIDTH - 2)))┘${NC}"
}

# 子标题:模块内的分组标题
print_subtitle() {
    echo
    echo -e "  ${BOLD}${BLUE}▸ $1${NC}"
}

# 计算字符串的终端显示宽度:中文/全角字符占 2 列,ASCII 占 1 列
# printf 的 %-16s 按字节补齐,中文 1 字符 3 字节会导致列错位,故所有含中文的标签都走这里
disp_width() {
    LC_ALL=C.UTF-8 awk -v s="$1" 'BEGIN {
        w = 0;
        n = length(s);
        for (i = 1; i <= n; i++) {
            c = substr(s, i, 1);
            # 非 ASCII 一律按 2 列计,覆盖中文、全角标点与方块绘图字符
            w += (c ~ /^[ -~]$/) ? 1 : 2;
        }
        print w;
    }'
}

# 把标签补齐到指定显示宽度;参数1=标签 参数2=目标宽度
pad_label() {
    local label="$1" target="$2" w pad=""
    w=$(disp_width "$label")
    local i
    for ((i = w; i < target; i++)); do pad="${pad} "; done
    echo "${label}${pad}"
}

# 标签统一显示宽度,所有 print_kv/print_kv2 共用,保证跨层级也对齐
LABEL_WIDTH=16

# 键值对输出,键按显示宽度对齐;参数1=键 参数2=值(可含颜色码)
print_kv() {
    echo -e "    $(pad_label "$1" $LABEL_WIDTH) $2"
}

# 缩进更深的键值对,用于设备明细内部
print_kv2() {
    echo -e "      $(pad_label "$1" $LABEL_WIDTH) $2"
}

# 设备条目标题:磁盘/网卡等单个设备的名字
print_device() {
    echo
    echo -e "    ${BOLD}${CYAN}● $1${NC}${2:+ ${GRAY}$2${NC}}"
}

# 表格表头;参数为 printf 格式串已格式化好的表头文本
print_thead() {
    echo -e "    ${GRAY}$1${NC}"
    echo -e "    ${GRAY}$(repeat_char '─' $((LINE_WIDTH - 6)))${NC}"
}

# 画一条百分比条;参数1=百分比 2=颜色 3=条宽(默认20)
# 输出形如 ████████░░░░░░░░░░░░
draw_bar() {
    local pct="$1" color="$2" width="${3:-20}"
    [ "$pct" -lt 0 ] 2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100
    local filled=$(( pct * width / 100 ))
    echo -e "${color}$(repeat_char '█' $filled)${GRAY}$(repeat_char '░' $((width - filled)))${NC}"
}

# 按阈值挑选颜色:值越大越危险;参数1=值 2=警告阈值 3=危险阈值
color_by_high() {
    local v="$1" warn="$2" crit="$3"
    if awk -v v="$v" -v c="$crit" 'BEGIN{exit !(v >= c)}'; then echo "$RED"
    elif awk -v v="$v" -v w="$warn" 'BEGIN{exit !(v >= w)}'; then echo "$YELLOW"
    else echo "$GREEN"; fi
}

# 按阈值挑选颜色:值越小越危险;参数1=值 2=警告阈值 3=危险阈值
color_by_low() {
    local v="$1" warn="$2" crit="$3"
    if [ "$v" -le "$crit" ] 2>/dev/null; then echo "$RED"
    elif [ "$v" -le "$warn" ] 2>/dev/null; then echo "$YELLOW"
    else echo "$GREEN"; fi
}

# 输出"使用率"行:进度条 + 百分比,统一样式
# 参数1=标签 2=百分比 3=尾注(可空)
print_usage_line() {
    local label="$1" pct="$2" note="$3"
    local color
    color=$(color_by_high "$pct" 75 90)
    echo -e "    $(pad_label "$label" $LABEL_WIDTH) $(draw_bar "${pct%.*}" "$color") ${color}$(printf '%5s' "$pct")%${NC}${note:+  $note}"
}

# ── 依赖检测 ──────────────────────────────────────────────────
# 检测包管理器,输出名称 (apt/dnf/yum/pacman/unknown)
detect_pkg_manager() {
    if command -v apt-get &>/dev/null; then
        echo "apt"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v yum &>/dev/null; then
        echo "yum"
    elif command -v pacman &>/dev/null; then
        echo "pacman"
    else
        echo "unknown"
    fi
}

# 把命令名映射为对应发行版的包名;参数1=命令 参数2=包管理器
pkg_name_for() {
    local cmd="$1" pm="$2"
    case "$cmd" in
        dmidecode) echo "dmidecode" ;;
        smartctl)  echo "smartmontools" ;;
        lspci)     echo "pciutils" ;;
        ethtool)   echo "ethtool" ;;
        nvme)      echo "nvme-cli" ;;
        sensors)
            # lm-sensors 在 Debian 系用连字符,RHEL/Arch 系用下划线
            case "$pm" in
                apt) echo "lm-sensors" ;;
                *) echo "lm_sensors" ;;
            esac
            ;;
        *) echo "$cmd" ;;
    esac
}

# 检查可选依赖,列出缺失项并询问是否安装;缺失不阻断,仅影响对应模块的信息完整度
check_dependencies() {
    local -a missing_cmds=()
    local cmd
    for cmd in dmidecode smartctl lspci ethtool; do
        command -v "$cmd" &>/dev/null || missing_cmds+=("$cmd")
    done

    [ ${#missing_cmds[@]} -eq 0 ] && return 0

    print_section "🔧 缺少可选工具"
    echo -e "    以下工具未安装,对应信息将无法展示。"
    echo -e "    ${GRAY}都是只读诊断工具:不含常驻服务、不开监听端口。${NC}"
    echo

    # 逐项说明用途,让用户判断是否值得装
    local cmd
    for cmd in "${missing_cmds[@]}"; do
        case "$cmd" in
            dmidecode)
                print_kv "dmidecode" "主板/BIOS 型号、${BOLD}内存条明细${NC}、电源模块"
                ;;
            smartctl)
                print_kv "smartmontools" "${BOLD}硬盘寿命、坏道、通电时长、盘温${NC}"
                ;;
            lspci)
                print_kv "pciutils" "网卡型号 ${GRAY}(驱动名不依赖它)${NC}"
                ;;
            ethtool)
                print_kv "ethtool" "网卡支持的最高速率 ${GRAY}(用于判断是否跑满)${NC}"
                ;;
        esac
    done

    local pm
    pm=$(detect_pkg_manager)
    if [ "$pm" = "unknown" ]; then
        echo
        log_warn "未识别的包管理器,请手动安装后重试"
        echo
        return 0
    fi

    # 命令去重映射为包名
    local -a pkgs=()
    local p
    for cmd in "${missing_cmds[@]}"; do
        p=$(pkg_name_for "$cmd" "$pm")
        [[ " ${pkgs[*]} " == *" $p "* ]] || pkgs+=("$p")
    done

    echo
    echo -e "    将通过 ${BOLD}${pm}${NC} 安装: ${BOLD}${pkgs[*]}${NC}"
    read -p "    是否现在安装? (Y/n): " choice
    choice=${choice:-Y}
    if [[ ! $choice =~ ^[Yy] ]]; then
        log_info "跳过安装,部分信息将显示为不可用"
        echo
        return 0
    fi

    local rc=0
    case "$pm" in
        apt) apt-get update && apt-get install -y "${pkgs[@]}" || rc=$? ;;
        dnf) dnf install -y "${pkgs[@]}" || rc=$? ;;
        yum) yum install -y "${pkgs[@]}" || rc=$? ;;
        pacman) pacman -Sy --noconfirm "${pkgs[@]}" || rc=$? ;;
    esac

    if [ "$rc" -eq 0 ]; then
        log_success "依赖安装完成"
        # 记录安装成功的包,退出时询问是否移除
        INSTALLED_PKGS=("${pkgs[@]}")
    else
        log_warn "依赖安装失败,部分信息将显示为不可用"
    fi
    echo
}

# 退出前询问是否移除本次新装的包;默认保留,便于下次复查硬件
# 只移除本脚本装的包,系统原有的同名包不会被记录也就不会被卸载
cleanup_installed_pkgs() {
    [ ${#INSTALLED_PKGS[@]} -eq 0 ] && return 0

    echo
    print_line
    echo -e "  本次运行安装了: ${BOLD}${INSTALLED_PKGS[*]}${NC}"
    echo -e "  ${GRAY}建议保留 — 硬件体检需要定期复查,留着下次可直接使用。${NC}"
    read -p "  是否移除这些包? (y/N): " choice
    if [[ ! $choice =~ ^[Yy] ]]; then
        log_info "已保留"
        return 0
    fi

    local pm rc=0
    pm=$(detect_pkg_manager)
    log_info "正在移除 ${INSTALLED_PKGS[*]}..."
    case "$pm" in
        apt) { apt-get remove -y --purge "${INSTALLED_PKGS[@]}" && apt-get autoremove -y; } || rc=$? ;;
        dnf) dnf remove -y "${INSTALLED_PKGS[@]}" || rc=$? ;;
        yum) yum remove -y "${INSTALLED_PKGS[@]}" || rc=$? ;;
        pacman) pacman -Rns --noconfirm "${INSTALLED_PKGS[@]}" || rc=$? ;;
        *) log_warn "未识别的包管理器,请手动移除"; return 1 ;;
    esac

    if [ "$rc" -eq 0 ]; then
        log_success "已移除本次安装的包"
        # 清空记录,避免 trap 与正常退出路径重复询问
        INSTALLED_PKGS=()
    else
        log_warn "移除过程出现错误,请手动检查"
    fi
}

# 检测虚拟化环境,输出虚拟化类型或 none
detect_virt() {
    if command -v systemd-detect-virt &>/dev/null; then
        systemd-detect-virt 2>/dev/null || echo "none"
    elif command -v virt-what &>/dev/null; then
        local v
        v=$(virt-what 2>/dev/null | head -n1)
        echo "${v:-none}"
    else
        # 无检测工具时从 DMI 产品名做粗判
        local product
        product=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
        case "$product" in
            *VMware*) echo "vmware" ;;
            *KVM*|*QEMU*) echo "kvm" ;;
            *VirtualBox*) echo "oracle" ;;
            *Virtual*Machine*) echo "microsoft" ;;
            *) echo "none" ;;
        esac
    fi
}

# 读取 DMI 字段,过滤掉厂商填的占位值 (To Be Filled By O.E.M. 等)
read_dmi() {
    local val
    val=$(cat "/sys/class/dmi/id/$1" 2>/dev/null)
    case "$val" in
        ""|*"To Be Filled"*|*"Not Specified"*|*"System Product Name"*|*"Default string"*|*"O.E.M."*)
            echo "未知"
            ;;
        *) echo "$val" ;;
    esac
}

# 把字节数换算为人类可读字符串
human_bytes() {
    awk -v b="$1" 'BEGIN {
        if (b >= 1099511627776) printf "%.2f TB", b/1099511627776;
        else if (b >= 1073741824) printf "%.2f GB", b/1073741824;
        else if (b >= 1048576) printf "%.2f MB", b/1048576;
        else if (b >= 1024) printf "%.2f KB", b/1024;
        else printf "%d B", b;
    }'
}

# ── 系统与主机概览 ────────────────────────────────────────────
show_system() {
    print_section "🖥️  系统与主机"

    local os_name
    if [ -f /etc/os-release ]; then
        os_name=$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")
    fi
    print_kv "主机名" "${BOLD}$(hostname)${NC}"
    print_kv "操作系统" "${os_name:-未知}"
    print_kv "内核版本" "$(uname -r)"
    print_kv "系统架构" "$(uname -m)"

    local uptime_str
    uptime_str=$(uptime -p 2>/dev/null | sed 's/^up //')
    print_kv "运行时长" "${uptime_str:-未知}"

    # 负载需结合核心数判断,一并给出逻辑核心数便于换算
    local loadavg cores load1
    loadavg=$(awk '{print $1"  "$2"  "$3}' /proc/loadavg 2>/dev/null)
    cores=$(nproc 2>/dev/null || echo 1)
    load1=$(awk '{print $1}' /proc/loadavg 2>/dev/null)
    local load_color=$GREEN
    if [ -n "$load1" ] && awk -v l="$load1" -v c="$cores" 'BEGIN{exit !(l > c)}'; then
        load_color=$YELLOW
        add_issue "WARN" "系统 1 分钟负载 ${load1} 超过逻辑核心数 ${cores}"
    fi
    print_kv "负载 1/5/15" "${load_color}${loadavg:-未知}${NC}  ${GRAY}(逻辑核心 ${cores})${NC}"

    local virt
    virt=$(detect_virt)
    if [ "$virt" = "none" ]; then
        print_kv "运行环境" "${GREEN}物理机 (裸金属)${NC}"
    else
        print_kv "运行环境" "${YELLOW}虚拟化: ${virt}${NC}"
    fi

    # 主板与整机型号:虚拟机下无实际意义,仅物理机展示
    if [ "$virt" = "none" ]; then
        print_subtitle "整机与主板"
        print_kv "整机型号" "$(read_dmi sys_vendor) $(read_dmi product_name)"
        print_kv "主板型号" "$(read_dmi board_vendor) $(read_dmi board_name)"
        print_kv "BIOS 版本" "$(read_dmi bios_version)  ${GRAY}($(read_dmi bios_date))${NC}"
    else
        echo
        log_warn "虚拟化环境下,硬盘 SMART、主板、温度等物理硬件信息可能不可用"
    fi
}

# ── CPU ───────────────────────────────────────────────────────
# 采样 1 秒计算 CPU 总使用率百分比,保留一位小数
get_cpu_usage() {
    local a b
    a=$(awk '/^cpu /{idle=$5+$6; total=0; for(i=2;i<=NF;i++) total+=$i; print idle, total}' /proc/stat 2>/dev/null)
    [ -z "$a" ] && return 1
    sleep 1
    b=$(awk '/^cpu /{idle=$5+$6; total=0; for(i=2;i<=NF;i++) total+=$i; print idle, total}' /proc/stat 2>/dev/null)
    [ -z "$b" ] && return 1
    awk -v a="$a" -v b="$b" 'BEGIN {
        split(a, x, " "); split(b, y, " ");
        dt = y[2] - x[2]; di = y[1] - x[1];
        if (dt <= 0) exit 1;
        printf "%.1f", (dt - di) * 100 / dt;
    }'
}

show_cpu() {
    print_section "🧠 CPU"

    if [ ! -f /proc/cpuinfo ]; then
        log_warn "无法读取 /proc/cpuinfo"
        return 0
    fi

    local model sockets cores_per_socket threads_total
    model=$(awk -F': ' '/^model name/ {print $2; exit}' /proc/cpuinfo)
    # ARM 平台无 model name,退回 Hardware / Model 字段
    [ -z "$model" ] && model=$(awk -F': ' '/^(Hardware|Model)/ {print $2; exit}' /proc/cpuinfo)
    threads_total=$(grep -c '^processor' /proc/cpuinfo)
    sockets=$(awk -F': ' '/^physical id/ {print $2}' /proc/cpuinfo | sort -u | wc -l)
    [ "$sockets" -eq 0 ] && sockets=1
    cores_per_socket=$(awk -F': ' '/^cpu cores/ {print $2; exit}' /proc/cpuinfo)

    print_kv "型号" "${BOLD}${model:-未知}${NC}"
    print_kv "物理 CPU" "${sockets} 颗"
    if [ -n "$cores_per_socket" ] && [ "$cores_per_socket" -gt 0 ] 2>/dev/null; then
        print_kv "物理核心" "$(( sockets * cores_per_socket )) 核  ${GRAY}(每颗 ${cores_per_socket} 核)${NC}"
    fi
    print_kv "逻辑线程" "${threads_total} 线程"

    # 频率:优先取 cpufreq 实时值,回退到 cpuinfo 的当前频率
    local cur_mhz max_mhz
    if [ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]; then
        cur_mhz=$(awk '{printf "%.0f", $1/1000}' /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)
        max_mhz=$(awk '{printf "%.0f", $1/1000}' /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null)
    fi
    [ -z "$cur_mhz" ] && cur_mhz=$(awk -F': ' '/^cpu MHz/ {printf "%.0f", $2; exit}' /proc/cpuinfo)
    if [ -n "$cur_mhz" ]; then
        if [ -n "$max_mhz" ] && [ "$max_mhz" -gt 0 ] 2>/dev/null; then
            print_kv "频率" "${cur_mhz} MHz  ${GRAY}/ 最高 ${max_mhz} MHz${NC}"
        else
            print_kv "频率" "${cur_mhz} MHz"
        fi
    fi

    local l3
    l3=$(awk -F': ' '/^cache size/ {print $2; exit}' /proc/cpuinfo)
    [ -n "$l3" ] && print_kv "缓存" "$l3"

    if grep -qE '^flags.*\b(vmx|svm)\b' /proc/cpuinfo 2>/dev/null; then
        print_kv "硬件虚拟化" "${GREEN}支持${NC}"
    fi

    # 使用率:取两次 /proc/stat 采样差值,避免依赖 top/mpstat
    local cpu_usage
    cpu_usage=$(get_cpu_usage)
    if [ -n "$cpu_usage" ]; then
        print_subtitle "实时负载"
        print_usage_line "CPU 使用率" "$cpu_usage"
        awk -v u="$cpu_usage" 'BEGIN{exit !(u >= 90)}' && add_issue "WARN" "CPU 使用率高达 ${cpu_usage}%"
    fi
}

# ── 内存 ──────────────────────────────────────────────────────
show_memory() {
    print_section "💾 内存"

    # 容量与使用率来自 /proc/meminfo,available 比 free 更贴近真实可用量
    local total_kb avail_kb used_kb usep
    total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null)
    avail_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null)
    # 3.14 之前的内核没有 MemAvailable,退回 free + buffers + cached 估算
    if [ -z "$avail_kb" ]; then
        avail_kb=$(awk '/^MemFree:|^Buffers:|^Cached:/ {s += $2} END {if (s > 0) print s}' /proc/meminfo 2>/dev/null)
    fi
    if [ -n "$total_kb" ] && [ -n "$avail_kb" ] && [ "$total_kb" -gt 0 ] 2>/dev/null; then
        used_kb=$(( total_kb - avail_kb ))
        # 估算值可能大于总量,钳到 0 避免出现负的已用量
        [ "$used_kb" -lt 0 ] && used_kb=0
        usep=$(awk -v u="$used_kb" -v t="$total_kb" 'BEGIN{printf "%.1f", u*100/t}')
        print_kv "总容量" "${BOLD}$(awk -v k="$total_kb" 'BEGIN{printf "%.1f GB", k/1048576}')${NC}"
        print_kv "已用 / 可用" "$(awk -v k="$used_kb" 'BEGIN{printf "%.1f GB", k/1048576}') ${GRAY}/${NC} $(awk -v k="$avail_kb" 'BEGIN{printf "%.1f GB", k/1048576}')"
        print_usage_line "使用率" "$usep"
        awk -v u="$usep" 'BEGIN{exit !(u >= 90)}' && add_issue "WARN" "内存使用率高达 ${usep}%"
    fi

    local swap_total swap_free swap_usep
    swap_total=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo 2>/dev/null)
    if [ -n "$swap_total" ] && [ "$swap_total" -gt 0 ]; then
        swap_free=$(awk '/^SwapFree:/ {print $2}' /proc/meminfo 2>/dev/null)
        swap_usep=$(awk -v u="$(( swap_total - swap_free ))" -v t="$swap_total" 'BEGIN{printf "%.1f", u*100/t}')
        print_kv "Swap" "$(awk -v k="$(( swap_total - swap_free ))" 'BEGIN{printf "%.1f GB", k/1048576}') ${GRAY}/${NC} $(awk -v k="$swap_total" 'BEGIN{printf "%.1f GB", k/1048576}')  ${GRAY}(${swap_usep}%)${NC}"
    else
        print_kv "Swap" "${GRAY}未启用${NC}"
    fi

    # 内存条明细:仅物理机可读,列出每条的位置/容量/类型/频率/厂商
    if ! command -v dmidecode &>/dev/null; then
        print_subtitle "内存条明细"
        echo -e "    ${GRAY}未安装 dmidecode,无法展示${NC}"
    elif [ "$(detect_virt)" != "none" ]; then
        print_subtitle "内存条明细"
        echo -e "    ${GRAY}虚拟化环境,不适用${NC}"
    else
        print_subtitle "内存条明细"
        # Size 为 "No Module Installed" 的是空槽位,单独计数不逐条展示
        local out
        out=$(dmidecode -t memory 2>/dev/null | awk '
            /^Memory Device/ {inblk=1; size=""; type=""; speed=""; loc=""; part=""; mfr=""; next}
            inblk && /^\t(Size|Type|Configured Memory Speed|Speed|Locator|Part Number|Manufacturer):/ {
                key=$0; sub(/^\t/, "", key); sub(/:.*/, "", key);
                val=$0; sub(/^[^:]*:[ \t]*/, "", val);
                if (key == "Size") size=val;
                else if (key == "Type") type=val;
                else if (key == "Configured Memory Speed" && val !~ /Unknown/) speed=val;
                else if (key == "Speed" && speed == "") speed=val;
                else if (key == "Locator") loc=val;
                else if (key == "Part Number") part=val;
                else if (key == "Manufacturer") mfr=val;
            }
            inblk && /^$/ {
                if (size != "") {
                    if (size ~ /No Module|Not Installed/) empty++;
                    else printf "    %-13s %-9s %-6s %-11s %s %s\n", substr(loc,1,13), size, type, speed, mfr, part;
                }
                inblk=0;
            }
            END { if (empty > 0) printf "    %s %s\n", "空闲插槽   ", empty " 个" }
        ')
        if [ -n "$out" ]; then
            print_thead "$(printf '%-13s %-9s %-6s %-11s %s' '插槽' '容量' '类型' '频率' '厂商/型号')"
            echo "$out"
        else
            echo -e "    ${GRAY}未能解析内存条信息${NC}"
        fi
    fi

    check_ecc_errors
}

# 检查 EDAC 上报的 ECC 错误计数,发现不可纠正错误直接记为严重告警
check_ecc_errors() {
    local edac_dir=/sys/devices/system/edac/mc
    [ -d "$edac_dir" ] || return 0

    local ce_total=0 ue_total=0 mc f v
    for mc in "$edac_dir"/mc*; do
        [ -d "$mc" ] || continue
        for f in ce_count ce_noinfo_count; do
            v=$(cat "$mc/$f" 2>/dev/null) && ce_total=$(( ce_total + ${v:-0} ))
        done
        for f in ue_count ue_noinfo_count; do
            v=$(cat "$mc/$f" 2>/dev/null) && ue_total=$(( ue_total + ${v:-0} ))
        done
    done

    print_subtitle "ECC 校验"
    if [ "$ue_total" -gt 0 ]; then
        print_kv "错误计数" "${RED}不可纠正 ${ue_total} 次${NC}  ${GRAY}/${NC}  可纠正 ${ce_total} 次"
        add_issue "CRIT" "内存出现 ${ue_total} 次不可纠正 ECC 错误,存在数据损坏风险,建议尽快更换内存"
    elif [ "$ce_total" -gt 0 ]; then
        print_kv "错误计数" "${YELLOW}可纠正 ${ce_total} 次${NC}"
        add_issue "WARN" "内存出现 ${ce_total} 次可纠正 ECC 错误,建议持续观察"
    else
        print_kv "错误计数" "${GREEN}无错误${NC}"
    fi
}

# ── 硬盘与 SMART ──────────────────────────────────────────────
show_disk() {
    print_section "💿 硬盘与健康状态"

    # 物理磁盘清单:排除 loop/ram/zram 等虚拟设备
    print_subtitle "磁盘设备"
    if command -v lsblk &>/dev/null; then
        print_thead "$(printf '%-10s %-9s %-6s %-26s %s' '设备' '容量' '类型' '型号' '序列号')"
        lsblk -dn -o NAME,SIZE,ROTA,TYPE,MODEL,SERIAL 2>/dev/null \
            | awk '$4 == "disk" {
                       kind = ($3 == "1") ? "HDD" : "SSD";
                       model = "";
                       for (i = 5; i < NF; i++) model = model (model == "" ? "" : " ") $i;
                       if (NF < 6) { model = ($5 == "" ? "-" : $5); serial = "-" } else { serial = $NF }
                       printf "    %-10s %-9s %-6s %-26s %s\n", $1, $2, kind, substr(model, 1, 26), serial;
                   }' 2>/dev/null || echo -e "    ${GRAY}无法读取磁盘列表${NC}"
    else
        echo -e "    ${GRAY}未安装 lsblk,无法列出磁盘设备${NC}"
    fi

    # 分区使用率:只看真实文件系统,跳过 tmpfs/overlay 等
    print_subtitle "分区使用率"
    print_thead "$(printf '%-22s %-8s %-7s %-7s %s' '挂载点' '文件系统' '总量' '可用' '使用率')"
    df -hTP 2>/dev/null | awk -v g="$(printf '\033[0;32m')" -v y="$(printf '\033[1;33m')" -v r="$(printf '\033[0;31m')" -v n="$(printf '\033[0m')" '
        NR > 1 && $2 !~ /^(tmpfs|devtmpfs|overlay|squashfs|efivarfs|ramfs|autofs|fuse.lxcfs)$/ {
            p = $6; sub(/%/, "", p);
            c = (p + 0 >= 90) ? r : ((p + 0 >= 75) ? y : g);
            printf "    %-22s %-8s %-7s %-7s %s%s%s\n", substr($7,1,22), $2, $3, $5, c, $6, n;
        }'

    # 使用率超过 85% 的分区记入告警
    local overfull
    overfull=$(df -hP 2>/dev/null | awk 'NR>1 && $5+0 >= 85 {print $6" ("$5")"}' | tr '\n' ' ')
    [ -n "$overfull" ] && add_issue "WARN" "分区使用率超过 85%: ${overfull}"

    # SMART 健康与寿命
    print_subtitle "SMART 健康与寿命"
    if ! command -v smartctl &>/dev/null; then
        echo -e "    ${GRAY}未安装 smartmontools,无法读取 SMART 信息${NC}"
        check_raid
        return 0
    fi

    local dev found=0
    for dev in $(lsblk -dn -o NAME,TYPE 2>/dev/null | awk '$2=="disk" {print $1}'); do
        case "$dev" in
            loop*|ram*|zram*|sr*|fd*) continue ;;
        esac
        found=1
        show_smart_one "/dev/$dev"
    done
    [ "$found" -eq 0 ] && echo -e "    ${GRAY}未找到可检测的物理磁盘${NC}"

    check_raid
}

# 展示单块磁盘的 SMART 概要;参数1=设备路径
# NVMe 与 SATA/SAS 的属性字段不同,分别解析
show_smart_one() {
    local dev="$1"
    local info health model

    # -i 拿型号,失败多为设备在 RAID 卡后面或不支持 SMART
    info=$(smartctl -i "$dev" 2>/dev/null)
    if ! echo "$info" | grep -q "SMART support is:\|Model Number\|Device Model\|Product:"; then
        print_device "$(basename "$dev")" "SMART 不可用 (可能位于 RAID 卡后或设备不支持)"
        return 0
    fi

    model=$(echo "$info" | awk -F': *' '/^(Device Model|Model Number|Product):/ {print $2; exit}')
    print_device "$(basename "$dev")" "$model"

    # 整体健康自评
    health=$(smartctl -H "$dev" 2>/dev/null | grep -iE "SMART overall-health|SMART Health Status" | sed 's/.*: *//')
    if [ -n "$health" ]; then
        if echo "$health" | grep -qiE "PASSED|OK"; then
            print_kv2 "整体健康" "${GREEN}✓ ${health}${NC}"
        else
            print_kv2 "整体健康" "${RED}✗ ${health}${NC}"
            add_issue "CRIT" "磁盘 ${dev} SMART 整体健康判定为 ${health},建议立即备份数据并更换"
        fi
    fi

    # 通电时长:两类盘的字段名不同,分别匹配
    local poh
    poh=$(smartctl -A "$dev" 2>/dev/null | awk '
        /Power_On_Hours/ {print $10; exit}
        /^Power On Hours:/ {gsub(/,/, "", $NF); print $NF; exit}')
    if [ -n "$poh" ] && [ "$poh" -gt 0 ] 2>/dev/null; then
        print_kv2 "通电时长" "${poh} 小时  ${GRAY}(约 $(( poh / 24 )) 天 / $(awk -v h="$poh" 'BEGIN{printf "%.1f", h/8760}') 年)${NC}"
    fi

    if echo "$info" | grep -q "NVMe"; then
        show_smart_nvme "$dev"
    else
        show_smart_ata "$dev"
    fi
}

# 输出剩余寿命行并按阈值记录告警;参数1=剩余百分比 2=设备
report_life() {
    local pct="$1" dev="$2"
    local color
    color=$(color_by_low "$pct" 20 10)
    echo -e "      $(pad_label "剩余寿命" $LABEL_WIDTH) $(draw_bar "$pct" "$color") ${color}$(printf '%3s' "$pct")%${NC}"
    if [ "$pct" -le 10 ] 2>/dev/null; then
        add_issue "CRIT" "磁盘 ${dev} 剩余寿命仅 ${pct}%,建议尽快更换"
    elif [ "$pct" -le 20 ] 2>/dev/null; then
        add_issue "WARN" "磁盘 ${dev} 剩余寿命 ${pct}%,建议提前准备更换"
    fi
}

# NVMe 盘寿命指标:percentage_used 是厂商给出的磨损百分比,100% 表示已达设计寿命
show_smart_nvme() {
    local dev="$1"
    local attrs
    attrs=$(smartctl -A "$dev" 2>/dev/null)
    [ -z "$attrs" ] && return 0

    local used spare media_err crit_warn temp written
    used=$(echo "$attrs" | awk -F: '/Percentage Used/ {gsub(/[ %]/, "", $2); print $2; exit}')
    spare=$(echo "$attrs" | awk -F: '/Available Spare:/ {gsub(/[ %]/, "", $2); print $2; exit}')
    media_err=$(echo "$attrs" | awk -F: '/Media and Data Integrity Errors/ {gsub(/[ ,]/, "", $2); print $2; exit}')
    crit_warn=$(echo "$attrs" | awk -F: '/Critical Warning/ {gsub(/[ ]/, "", $2); print $2; exit}')
    temp=$(echo "$attrs" | awk -F: '/^Temperature:/ {gsub(/[ ]/, "", $2); sub(/Celsius/, "", $2); print $2; exit}')
    written=$(echo "$attrs" | awk -F: '/Data Units Written/ {print $2; exit}' | sed 's/^ *//')

    if [ -n "$used" ]; then
        local life=$(( 100 - used ))
        [ "$life" -lt 0 ] && life=0
        report_life "$life" "$dev"
    fi

    if [ -n "$spare" ]; then
        # 备用块低于 10% 是 NVMe 临近失效的关键信号
        if [ "$spare" -lt 10 ] 2>/dev/null; then
            print_kv2 "可用备用块" "${RED}${spare}%${NC}"
            add_issue "CRIT" "磁盘 ${dev} 可用备用块仅剩 ${spare}%,接近失效"
        else
            print_kv2 "可用备用块" "${GREEN}${spare}%${NC}"
        fi
    fi

    if [ -n "$media_err" ] && [ "$media_err" -gt 0 ] 2>/dev/null; then
        print_kv2 "介质错误" "${RED}${media_err}${NC}"
        add_issue "CRIT" "磁盘 ${dev} 存在 ${media_err} 个介质/数据完整性错误"
    else
        print_kv2 "介质错误" "${GREEN}0${NC}"
    fi

    if [ -n "$crit_warn" ] && [ "$crit_warn" != "0x00" ] && [ "$crit_warn" != "0" ]; then
        print_kv2 "严重警告位" "${RED}${crit_warn}${NC}"
        add_issue "CRIT" "磁盘 ${dev} 上报 NVMe 严重警告位 ${crit_warn}"
    fi

    [ -n "$written" ] && print_kv2 "累计写入" "${GRAY}${written}${NC}"
    print_disk_temp "$temp"
}

# SATA/SAS 盘健康:关注重映射扇区、待定扇区、不可纠正扇区,以及 SSD 的寿命属性
show_smart_ata() {
    local dev="$1"
    local attrs
    attrs=$(smartctl -A "$dev" 2>/dev/null)
    [ -z "$attrs" ] && return 0

    # SSD 寿命:不同厂商用不同属性名,依次尝试;取归一化值 (VALUE 列) 作为剩余百分比
    local life
    life=$(echo "$attrs" | awk '
        /Percent_Lifetime_Remain/ {print $4; exit}
        /Wear_Leveling_Count/ {print $4; exit}
        /Media_Wearout_Indicator/ {print $4; exit}
        /SSD_Life_Left/ {print $4; exit}
        /Remaining_Lifetime_Perc/ {print $4; exit}')
    if [ -n "$life" ]; then
        # 归一化值带前导零 (如 097),强制按十进制解析
        life=$((10#$life))
        report_life "$life" "$dev"
    fi

    # 坏道类属性:原始值非 0 即需关注,持续增长代表盘体劣化
    local realloc pending offline crc
    realloc=$(echo "$attrs" | awk '/Reallocated_Sector_Ct/ {print $10; exit}')
    pending=$(echo "$attrs" | awk '/Current_Pending_Sector/ {print $10; exit}')
    offline=$(echo "$attrs" | awk '/Offline_Uncorrectable/ {print $10; exit}')
    crc=$(echo "$attrs" | awk '/UDMA_CRC_Error_Count/ {print $10; exit}')

    print_sector_attr "重映射扇区" "$realloc" "$dev" "重映射扇区"
    print_sector_attr "待定扇区" "$pending" "$dev" "待定坏扇区"
    print_sector_attr "不可纠正扇区" "$offline" "$dev" "不可纠正扇区"

    # CRC 错误通常是数据线/背板接触问题,不代表盘体损坏,单独提示
    if [ -n "$crc" ] && [ "$crc" -gt 0 ] 2>/dev/null; then
        print_kv2 "CRC 错误" "${YELLOW}${crc}${NC}  ${GRAY}(多为数据线/背板接触问题)${NC}"
        add_issue "WARN" "磁盘 ${dev} 存在 ${crc} 次 UDMA CRC 错误,建议检查数据线与背板接触"
    fi

    local temp
    temp=$(echo "$attrs" | awk '/Temperature_Celsius|Airflow_Temperature/ {print $10; exit}')
    print_disk_temp "$temp"
}

# 展示磁盘温度并按阈值上色;参数1=摄氏度
print_disk_temp() {
    local temp="$1"
    [ -z "$temp" ] && return 0
    [[ "$temp" =~ ^[0-9]+$ ]] || return 0
    local color
    color=$(color_by_high "$temp" 55 65)
    print_kv2 "温度" "${color}${temp}°C${NC}"
}

# 输出一项坏道类属性,非 0 标红并记入告警
# 参数: 1=显示名 2=值 3=设备 4=告警描述用名
print_sector_attr() {
    local label="$1" val="$2" dev="$3" desc="$4"
    [ -z "$val" ] && return 0
    if [ "$val" -gt 0 ] 2>/dev/null; then
        print_kv2 "$label" "${RED}${val}${NC}"
        add_issue "CRIT" "磁盘 ${dev} 存在 ${val} 个${desc},建议备份数据并评估更换"
    else
        print_kv2 "$label" "${GREEN}0${NC}"
    fi
}

# 检查 mdraid 软阵列状态;硬件 RAID 需厂商工具,此处不覆盖
check_raid() {
    [ -f /proc/mdstat ] || return 0
    grep -q '^md' /proc/mdstat 2>/dev/null || return 0

    print_subtitle "软 RAID (mdraid)"
    # [UU] 全 U 为健康,出现 _ 表示有成员盘掉线
    local md state
    for md in $(awk '/^md/ {print $1}' /proc/mdstat); do
        state=$(grep -A2 "^${md} " /proc/mdstat | grep -oE '\[[U_]+\]' | head -n1)
        if [ -z "$state" ]; then
            print_kv "$md" "${GRAY}状态未知${NC}"
        elif [[ "$state" == *_* ]]; then
            print_kv "$md" "${RED}✗ ${state} 阵列降级${NC}"
            add_issue "CRIT" "软 RAID 阵列 ${md} 处于降级状态 ${state},存在成员盘掉线"
        else
            print_kv "$md" "${GREEN}✓ ${state} 正常${NC}"
        fi
    done

    # 重建/同步进度
    local resync
    resync=$(grep -E 'recovery|resync|check' /proc/mdstat 2>/dev/null | head -n1 | sed 's/^ *//')
    [ -n "$resync" ] && echo -e "    ${YELLOW}${resync}${NC}"
}

# ── 网卡 ──────────────────────────────────────────────────────
show_network() {
    print_section "🌐 网卡与网络"

    local iface found=0
    for iface in /sys/class/net/*; do
        [ -e "$iface" ] || continue
        local name
        name=$(basename "$iface")

        # 只看物理网卡与 bond:虚拟设备 (docker/veth/br/tun/lo) 对硬件概览无意义
        case "$name" in
            lo|docker*|veth*|br-*|virbr*|tun*|tap*|wg*|zt*|kube*|cni*|flannel*|dummy*) continue ;;
        esac
        # 有 device 软链的才是真实硬件;bond 无 device 但需要展示
        if [ ! -e "$iface/device" ] && [ ! -e "$iface/bonding" ]; then
            continue
        fi

        [ "$found" -eq 0 ] && print_subtitle "物理网卡"
        found=1
        show_nic_one "$name"
    done
    if [ "$found" -eq 0 ]; then
        print_subtitle "物理网卡"
        echo -e "    ${GRAY}未找到物理网卡${NC}"
    fi

    show_bonding
    show_public_ip
}

# 展示单块网卡的型号/驱动/MAC/连接状态/协商速率/IP;参数1=网卡名
show_nic_one() {
    local name="$1"
    local sysdir="/sys/class/net/$name"

    # 连接状态先取,后续速率读取依赖它
    local operstate
    operstate=$(cat "$sysdir/operstate" 2>/dev/null)

    local status_tag
    if [ "$operstate" = "up" ]; then
        status_tag="${GREEN}● 已连接${NC}"
    else
        status_tag="${YELLOW}○ ${operstate:-未知}${NC}"
    fi
    echo
    echo -e "    ${BOLD}${CYAN}● ${name}${NC}   ${status_tag}"

    # 网卡型号:优先从 lspci 取,回退到驱动名
    local model driver
    driver=$(basename "$(readlink -f "$sysdir/device/driver" 2>/dev/null)" 2>/dev/null)
    if command -v lspci &>/dev/null && [ -e "$sysdir/device" ]; then
        # PCI 地址形如 0000:01:00.0,lspci -s 用不带域的短地址
        local pci_addr
        pci_addr=$(basename "$(readlink -f "$sysdir/device" 2>/dev/null)" 2>/dev/null)
        if [[ "$pci_addr" =~ ^[0-9a-f]{4}: ]]; then
            model=$(lspci -s "${pci_addr#*:}" 2>/dev/null | sed 's/^[^ ]* //' | sed 's/^[^:]*: //')
        fi
    fi
    print_kv2 "型号" "${model:-未知}"
    print_kv2 "驱动" "${driver:-未知}"
    print_kv2 "MAC 地址" "$(cat "$sysdir/address" 2>/dev/null || echo 未知)"

    # 协商速率与双工:sysfs 的 speed 单位为 Mb/s,链路 down 时读取会报错
    local speed duplex
    if [ "$operstate" = "up" ]; then
        speed=$(cat "$sysdir/speed" 2>/dev/null)
        duplex=$(cat "$sysdir/duplex" 2>/dev/null)
    fi
    if [ -n "$speed" ] && [ "$speed" -gt 0 ] 2>/dev/null; then
        local speed_str
        if [ "$speed" -ge 1000 ]; then
            speed_str="$(awk -v s="$speed" 'BEGIN{printf "%g", s/1000}') Gbps"
        else
            speed_str="${speed} Mbps"
        fi
        print_kv2 "协商速率" "${BOLD}${speed_str}${NC}${duplex:+  ${GRAY}${duplex}工${NC}}"
        check_nic_negotiation "$name" "$speed"
    elif [ "$operstate" = "up" ]; then
        print_kv2 "协商速率" "${GRAY}未知${NC}"
    fi

    print_kv2 "MTU" "$(cat "$sysdir/mtu" 2>/dev/null || echo 未知)"

    # 本机 IP:同一网卡可能绑定多个地址
    local ips
    ips=$(ip -o addr show dev "$name" 2>/dev/null | awk '$3=="inet" || $3=="inet6" {print $4}' | tr '\n' ' ')
    print_kv2 "IP 地址" "${ips:-无}"

    # 收发流量与错误包
    local rx_b tx_b rx_e tx_e rx_d tx_d
    rx_b=$(cat "$sysdir/statistics/rx_bytes" 2>/dev/null || echo 0)
    tx_b=$(cat "$sysdir/statistics/tx_bytes" 2>/dev/null || echo 0)
    print_kv2 "累计流量" "↓ $(human_bytes "$rx_b")   ↑ $(human_bytes "$tx_b")"

    rx_e=$(cat "$sysdir/statistics/rx_errors" 2>/dev/null || echo 0)
    tx_e=$(cat "$sysdir/statistics/tx_errors" 2>/dev/null || echo 0)
    rx_d=$(cat "$sysdir/statistics/rx_dropped" 2>/dev/null || echo 0)
    tx_d=$(cat "$sysdir/statistics/tx_dropped" 2>/dev/null || echo 0)
    if [ "$(( rx_e + tx_e ))" -gt 0 ]; then
        print_kv2 "错误包" "${YELLOW}收 ${rx_e} / 发 ${tx_e}${NC}"
        add_issue "WARN" "网卡 ${name} 存在错误包 (收 ${rx_e} / 发 ${tx_e}),建议检查链路质量"
    else
        print_kv2 "错误包" "${GREEN}0${NC}"
    fi
    [ "$(( rx_d + tx_d ))" -gt 0 ] && print_kv2 "丢弃包" "${GRAY}收 ${rx_d} / 发 ${tx_d}${NC}"
}

# 比对实际协商速率与网卡支持的最高速率,偏低时告警;参数1=网卡名 2=当前速率(Mb/s)
check_nic_negotiation() {
    local name="$1" cur="$2"
    command -v ethtool &>/dev/null || return 0

    # 从 supported link modes 段落中取出最大速率数字 (形如 1000baseT/Full)
    local max
    max=$(ethtool "$name" 2>/dev/null | awk '
        /Supported link modes:/ {inblk=1}
        inblk && /Supported pause frame use:/ {inblk=0}
        inblk {
            n = split($0, arr, /[ \t]+/);
            for (i = 1; i <= n; i++) if (arr[i] ~ /^[0-9]+base/) {
                sub(/base.*/, "", arr[i]);
                if (arr[i] + 0 > m) m = arr[i] + 0;
            }
        }
        END { if (m > 0) print m }')

    [ -z "$max" ] && return 0
    if [ "$cur" -lt "$max" ] 2>/dev/null; then
        print_kv2 "支持最高" "${YELLOW}${max} Mbps${NC}  ${GRAY}(未跑满,建议检查网线/对端端口)${NC}"
        add_issue "WARN" "网卡 ${name} 协商速率 ${cur} Mbps 低于支持的 ${max} Mbps"
    else
        print_kv2 "支持最高" "${GREEN}${max} Mbps  (已跑满)${NC}"
    fi
}

# 展示 bond 聚合口的模式与成员状态
show_bonding() {
    [ -d /proc/net/bonding ] || return 0
    local f
    for f in /proc/net/bonding/*; do
        [ -f "$f" ] || continue
        print_subtitle "链路聚合 $(basename "$f")"
        local mode
        mode=$(awk -F': ' '/Bonding Mode/ {print $2; exit}' "$f")
        print_kv "模式" "${mode:-未知}"
        # 成员口状态:任一 down 说明聚合已降级
        local slave state
        while read -r slave state; do
            [ -z "$slave" ] && continue
            if [ "$state" = "up" ]; then
                print_kv "成员 $slave" "${GREEN}up${NC}"
            else
                print_kv "成员 $slave" "${YELLOW}${state}${NC}"
            fi
        done < <(awk -F': ' '
            /^Slave Interface/ {slave=$2}
            /^MII Status/ && slave != "" {print slave, $2; slave=""}
        ' "$f")
        if grep -q "^MII Status: down" "$f" 2>/dev/null; then
            add_issue "WARN" "链路聚合 $(basename "$f") 存在 down 状态的成员口"
        fi
    done
}

# 查询公网出口 IP;只接受纯文本 IP 端点,并校验格式
# 校验必不可少:某些端点/劫持页会返回整页 HTML,直接打印会污染报告
query_public_ip() {
    local ver="$1" url resp
    for url in "https://api.ipify.org" "https://icanhazip.com" "https://ifconfig.me/ip"; do
        resp=$(curl -s "-$ver" --max-time 3 "$url" 2>/dev/null | tr -d '\r\n[:space:]')
        # 长度与字符集双重校验,排除 HTML 页面与错误文案
        [ ${#resp} -gt 45 ] && continue
        if [ "$ver" = "4" ]; then
            [[ "$resp" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] && { echo "$resp"; return 0; }
        else
            [[ "$resp" =~ ^[0-9a-fA-F:]+$ && "$resp" == *:* ]] && { echo "$resp"; return 0; }
        fi
    done
    return 1
}

# 展示公网出口 IP,3 秒超时,失败不阻断
show_public_ip() {
    command -v curl &>/dev/null || return 0

    print_subtitle "公网出口"
    local ip4 ip6
    if ip4=$(query_public_ip 4); then
        print_kv "IPv4" "$ip4"
    else
        print_kv "IPv4" "${GRAY}查询失败或无 IPv4 出口${NC}"
    fi

    if ip6=$(query_public_ip 6); then
        print_kv "IPv6" "$ip6"
    fi
}

# ── 温度与电源 ────────────────────────────────────────────────
show_sensors() {
    print_section "🌡️  温度与电源"

    local printed=0
    # 优先 sensors,输出更全 (含风扇/电压)
    if command -v sensors &>/dev/null; then
        local out
        out=$(sensors 2>/dev/null | grep -E "Package id|Core |Tctl|Tdie|temp[0-9]|fan[0-9]" | head -n 14)
        if [ -n "$out" ]; then
            print_subtitle "传感器读数"
            echo "$out" | sed 's/^/    /'
            printed=1
        fi
    fi

    # 回退到 thermal_zone,temp 单位为毫摄氏度
    if [ "$printed" -eq 0 ]; then
        local zone t type c
        for zone in /sys/class/thermal/thermal_zone*; do
            [ -r "$zone/temp" ] || continue
            t=$(cat "$zone/temp" 2>/dev/null)
            type=$(cat "$zone/type" 2>/dev/null)
            [ -z "$t" ] && continue
            if [ "$printed" -eq 0 ]; then
                print_subtitle "温度传感器"
                printed=1
            fi
            local celsius
            celsius=$(awk -v v="$t" 'BEGIN{printf "%.1f", v/1000}')
            c=$(color_by_high "$celsius" 70 85)
            printf "    %-20s %b%s°C%b\n" "$type" "$c" "$celsius" "$NC"
            if awk -v v="$celsius" 'BEGIN{exit !(v >= 85)}'; then
                add_issue "WARN" "温度传感器 ${type} 读数 ${celsius}°C 偏高"
            fi
        done
    fi

    if [ "$printed" -eq 0 ]; then
        print_subtitle "温度传感器"
        echo -e "    ${GRAY}未检测到可用传感器 (可安装 lm-sensors 并执行 sensors-detect)${NC}"
    fi

    # 电源模块状态:仅部分服务器主板通过 DMI type 39 暴露
    if command -v dmidecode &>/dev/null && [ "$(detect_virt)" = "none" ]; then
        local psu
        psu=$(dmidecode -t 39 2>/dev/null | awk -F': ' '
            /Name:/ {name=$2}
            /Status:/ {if (name != "") {printf "    %-28s %s\n", name, $2; name=""}}')
        if [ -n "$psu" ]; then
            print_subtitle "电源模块"
            echo "$psu"
        fi
    fi
}

# ── 健康体检汇总 ──────────────────────────────────────────────
show_health_summary() {
    echo
    echo -e "${CYAN}╔$(repeat_char '═' $((LINE_WIDTH - 2)))╗${NC}"
    echo -e "${CYAN}║${NC} ${BOLD}🩺 健康体检结论${NC}"
    echo -e "${CYAN}╚$(repeat_char '═' $((LINE_WIDTH - 2)))╝${NC}"

    if [ ${#HEALTH_ISSUES[@]} -eq 0 ]; then
        echo
        echo -e "    ${GREEN}${BOLD}✅ 未发现异常,各项指标正常${NC}"
        echo
        return 0
    fi

    local item level desc crit_count=0 warn_count=0
    for item in "${HEALTH_ISSUES[@]}"; do
        if [ "${item%%|*}" = "CRIT" ]; then
            crit_count=$(( crit_count + 1 ))
        else
            warn_count=$(( warn_count + 1 ))
        fi
    done

    echo
    echo -e "    共发现 ${RED}${BOLD}${crit_count}${NC} 项严重问题, ${YELLOW}${BOLD}${warn_count}${NC} 项警告"
    echo

    # 严重问题优先展示
    for item in "${HEALTH_ISSUES[@]}"; do
        level="${item%%|*}"
        desc="${item#*|}"
        [ "$level" = "CRIT" ] && echo -e "    ${RED}✗ [严重]${NC} $desc"
    done
    for item in "${HEALTH_ISSUES[@]}"; do
        level="${item%%|*}"
        desc="${item#*|}"
        [ "$level" = "WARN" ] && echo -e "    ${YELLOW}⚠ [警告]${NC} $desc"
    done
    echo
}

# 执行全部检测项;每次重新采集前清空历史告警,避免重复累积
run_full_check() {
    HEALTH_ISSUES=()
    show_system
    show_cpu
    show_memory
    show_disk
    show_network
    show_sensors
    show_health_summary
}

# 导出报告到文件:去除颜色码,便于粘贴与留档
export_report() {
    local default_file="/tmp/hardware_report_$(hostname)_$(date +%Y%m%d_%H%M%S).txt"
    read -p "报告保存路径 (默认 ${default_file}): " out_file
    out_file=${out_file:-$default_file}

    local out_dir
    out_dir=$(dirname "$out_file")
    if [ ! -d "$out_dir" ]; then
        log_error "目录不存在: $out_dir"
        return 1
    fi

    log_info "正在采集硬件信息 (CPU 使用率采样需约 1 秒)..."
    # 去掉 ANSI 颜色转义序列,纯文本落盘
    if run_full_check 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$out_file"; then
        log_success "报告已保存: $out_file"
        echo -e "${CYAN}查看: cat ${out_file}${NC}"
    else
        log_error "报告导出失败"
        return 1
    fi
}

# 主菜单
show_menu() {
    echo -e "${CYAN}╔$(repeat_char '═' $((LINE_WIDTH - 2)))╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}🖥️  独服硬件配置与健康概览${NC}"
    echo -e "${CYAN}╚$(repeat_char '═' $((LINE_WIDTH - 2)))╝${NC}"
    echo
    echo -e "  ${BOLD}${BLUE}1)${NC} 完整体检          ${GRAY}全部硬件 + 健康结论${NC}"
    echo -e "  ${BOLD}${BLUE}2)${NC} 系统与主机        ${GRAY}整机/主板/BIOS/负载${NC}"
    echo -e "  ${BOLD}${BLUE}3)${NC} CPU               ${GRAY}型号/核心/频率/使用率${NC}"
    echo -e "  ${BOLD}${BLUE}4)${NC} 内存              ${GRAY}容量/内存条明细/ECC${NC}"
    echo -e "  ${BOLD}${BLUE}5)${NC} 硬盘与 SMART      ${GRAY}容量/寿命/坏道/RAID${NC}"
    echo -e "  ${BOLD}${BLUE}6)${NC} 网卡              ${GRAY}型号/协商速率/错误包${NC}"
    echo -e "  ${BOLD}${BLUE}7)${NC} 温度与电源        ${GRAY}传感器读数/电源模块${NC}"
    echo -e "  ${BOLD}${BLUE}8)${NC} 导出报告          ${GRAY}保存纯文本体检报告${NC}"
    echo
    echo -e "  ${BOLD}${RED}0)${NC} 退出"
    echo
    print_line
}

# 主流程
main() {
    check_dependencies

    while true; do
        show_menu
        read -p "请输入选项 [0-8]: " choice
        case "$choice" in
            1) run_full_check ;;
            2) HEALTH_ISSUES=(); show_system ;;
            3) HEALTH_ISSUES=(); show_cpu ;;
            4) HEALTH_ISSUES=(); show_memory ;;
            5) HEALTH_ISSUES=(); show_disk; show_health_summary ;;
            6) HEALTH_ISSUES=(); show_network; show_health_summary ;;
            7) HEALTH_ISSUES=(); show_sensors ;;
            8) export_report ;;
            0)
                cleanup_installed_pkgs
                log_info "退出硬件概览工具"
                exit 0
                ;;
            *)
                echo
                log_warn "无效选项,请重新选择"
                ;;
        esac
        echo
        echo -e "${GRAY}按任意键返回菜单...${NC}"
        read -n 1 -s
        echo
    done
}

# 中断时也走一次清理询问,避免 Ctrl+C 后遗留本次安装的包
trap 'echo; cleanup_installed_pkgs; echo -e "${YELLOW}已中断${NC}"; exit 130' INT TERM

main "$@"
