#!/bin/bash

# Journal 日志清理与限制脚本
# 清理 systemd-journald 累积日志,并设置上限避免日志再次膨胀
# 适用于使用 systemd 的所有主流发行版

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# 配置常量
JOURNALD_CONF="/etc/systemd/journald.conf"
BACKUP_DIR="/etc/uls/backup"

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

# 检查 systemd-journald 是否可用
check_journald() {
    if ! command -v journalctl &>/dev/null; then
        log_error "未检测到 journalctl 命令,当前系统可能未使用 systemd-journald"
        exit 1
    fi
    if ! systemctl list-unit-files 2>/dev/null | grep -q '^systemd-journald'; then
        log_warn "未找到 systemd-journald 服务单元,部分操作可能失败"
    fi
}

# 分隔线
print_separator() {
    echo -e "${CYAN}────────────────────────────────────────────────────${NC}"
}

# 显示当前 journal 占用
show_disk_usage() {
    echo -e "${BOLD}当前 Journal 磁盘占用:${NC}"
    journalctl --disk-usage 2>/dev/null || log_warn "无法获取 journal 磁盘占用"
}

# 备份配置文件
backup_config() {
    if [ ! -f "$JOURNALD_CONF" ]; then
        log_warn "配置文件不存在: $JOURNALD_CONF (将创建新文件)"
        return 0
    fi
    mkdir -p "$BACKUP_DIR"
    local backup_file="$BACKUP_DIR/journald.conf.$(date +%Y%m%d_%H%M%S).bak"
    cp "$JOURNALD_CONF" "$backup_file"
    log_success "已备份原配置: $backup_file"
}

# 清理 journal 日志
clean_journal() {
    print_separator
    echo -e "${BOLD}🗑️  清理 Journal 日志${NC}"
    print_separator
    echo "请选择清理策略:"
    echo "  1) 按时间清理 - 仅保留最近 N 天"
    echo "  2) 按大小清理 - 仅保留 N 大小"
    echo "  3) 跳过清理"
    echo
    read -p "请选择 [1-3] (默认 1): " clean_choice
    clean_choice=${clean_choice:-1}

    case "$clean_choice" in
        1)
            read -p "保留天数 (默认 7): " keep_days
            keep_days=${keep_days:-7}
            if ! [[ "$keep_days" =~ ^[0-9]+$ ]] || [ "$keep_days" -lt 1 ]; then
                log_error "无效的天数: $keep_days"
                return 1
            fi
            log_info "正在清理 ${keep_days} 天前的日志..."
            journalctl --vacuum-time="${keep_days}d"
            log_success "按时间清理完成"
            ;;
        2)
            read -p "保留大小 (例: 200M / 1G,默认 200M): " keep_size
            keep_size=${keep_size:-200M}
            if ! [[ "$keep_size" =~ ^[0-9]+[KMGTkmgt]?$ ]]; then
                log_error "无效的大小格式: $keep_size"
                return 1
            fi
            log_info "正在清理日志,保留 ${keep_size}..."
            journalctl --vacuum-size="${keep_size}"
            log_success "按大小清理完成"
            ;;
        3)
            log_info "跳过清理"
            ;;
        *)
            log_warn "无效选择,跳过清理"
            ;;
    esac
}

# 写入配置项 (覆盖或追加)
set_conf_value() {
    local key="$1"
    local value="$2"
    local file="$3"

    # 如果存在 (含被注释的) 该 key,替换为新值;否则追加
    if grep -qE "^[#[:space:]]*${key}=" "$file" 2>/dev/null; then
        sed -i -E "s|^[#[:space:]]*${key}=.*|${key}=${value}|" "$file"
    else
        echo "${key}=${value}" >> "$file"
    fi
}

# 配置 journal 大小限制
configure_limits() {
    print_separator
    echo -e "${BOLD}⚙️  配置 Journal 大小上限${NC}"
    print_separator
    echo "为避免日志再次膨胀,建议设置以下上限:"
    echo "  • SystemMaxUse      - journal 总占用上限"
    echo "  • SystemMaxFileSize - 单个 journal 文件上限"
    echo "  • MaxRetentionSec   - 日志最长保留时间"
    echo
    read -p "是否配置大小限制? (Y/n): " config_choice
    config_choice=${config_choice:-Y}

    if [[ ! $config_choice =~ ^[Yy] ]]; then
        log_info "跳过配置"
        return 0
    fi

    read -p "SystemMaxUse (默认 200M): " max_use
    max_use=${max_use:-200M}
    read -p "SystemMaxFileSize (默认 50M): " max_file
    max_file=${max_file:-50M}
    read -p "MaxRetentionSec (默认 2week,可填如 7day/1month): " retention
    retention=${retention:-2week}

    # 备份并写入
    backup_config

    # 确保 [Journal] 节存在
    if [ ! -f "$JOURNALD_CONF" ]; then
        echo "[Journal]" > "$JOURNALD_CONF"
    elif ! grep -qE '^\[Journal\]' "$JOURNALD_CONF"; then
        echo "" >> "$JOURNALD_CONF"
        echo "[Journal]" >> "$JOURNALD_CONF"
    fi

    set_conf_value "SystemMaxUse" "$max_use" "$JOURNALD_CONF"
    set_conf_value "SystemMaxFileSize" "$max_file" "$JOURNALD_CONF"
    set_conf_value "MaxRetentionSec" "$retention" "$JOURNALD_CONF"

    log_success "配置已写入 $JOURNALD_CONF"

    # 重启服务生效
    log_info "正在重启 systemd-journald..."
    if systemctl restart systemd-journald; then
        log_success "systemd-journald 已重启,配置生效"
    else
        log_error "重启失败,请手动检查: systemctl status systemd-journald"
        return 1
    fi
}

# 显示生效后的状态
show_result() {
    print_separator
    echo -e "${BOLD}✅ 操作完成,当前状态:${NC}"
    print_separator
    show_disk_usage
    echo
    echo -e "${BOLD}当前关键配置:${NC}"
    grep -E '^(SystemMaxUse|SystemMaxFileSize|MaxRetentionSec)=' "$JOURNALD_CONF" 2>/dev/null \
        || log_info "未在配置文件中显式设置上述参数 (使用默认值)"
}

# 主流程
main() {
    print_separator
    echo -e "${BOLD}${CYAN}🧹 Journal 日志清理与限制工具${NC}"
    print_separator
    check_journald
    show_disk_usage
    echo

    clean_journal
    echo
    configure_limits
    echo
    show_result
}

main "$@"
