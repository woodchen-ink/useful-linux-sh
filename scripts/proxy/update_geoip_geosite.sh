#!/bin/bash

# XrayR 路由规则文件更新脚本
# 功能: 更新 geosite.dat 和 geoip.dat 规则文件
# 作者: ULS
# 版本: 1.0

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# XrayR 配置目录
XRAYR_DIR="/etc/XrayR"

# 规则文件下载地址
GEOSITE_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"
GEOIP_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要 root 权限运行"
        echo "请使用 sudo 或切换到 root 用户后执行"
        exit 1
    fi
}

# 检查必要的命令
check_dependencies() {
    local missing_deps=()

    for cmd in wget curl; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "缺少必要的命令: ${missing_deps[*]}"
        log_info "正在尝试安装依赖..."

        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y "${missing_deps[@]}"
        elif command -v yum &> /dev/null; then
            yum install -y "${missing_deps[@]}"
        elif command -v dnf &> /dev/null; then
            dnf install -y "${missing_deps[@]}"
        else
            log_error "无法自动安装依赖,请手动安装: ${missing_deps[*]}"
            exit 1
        fi
    fi
}

# 检查 XrayR 是否安装
check_xrayr() {
    if [ ! -d "$XRAYR_DIR" ]; then
        log_error "未检测到 XrayR 安装目录: $XRAYR_DIR"
        echo "请确认 XrayR 已正确安装"
        return 1
    fi

    if ! command -v XrayR &> /dev/null; then
        log_warning "未找到 XrayR 命令,可能无法自动重启服务"
        return 2
    fi

    return 0
}

# 检查规则文件是否存在
check_rule_files() {
    log_info "检查现有规则文件..."

    local geosite_exists=false
    local geoip_exists=false

    if [ -f "$XRAYR_DIR/geosite.dat" ]; then
        geosite_exists=true
        local geosite_size=$(du -h "$XRAYR_DIR/geosite.dat" | cut -f1)
        local geosite_date=$(stat -c %y "$XRAYR_DIR/geosite.dat" 2>/dev/null | cut -d' ' -f1)
        [ -z "$geosite_date" ] && geosite_date=$(stat -f %Sm -t "%Y-%m-%d" "$XRAYR_DIR/geosite.dat" 2>/dev/null)
        log_info "已存在 geosite.dat (大小: $geosite_size, 修改日期: $geosite_date)"
    else
        log_warning "未找到 geosite.dat 文件"
    fi

    if [ -f "$XRAYR_DIR/geoip.dat" ]; then
        geoip_exists=true
        local geoip_size=$(du -h "$XRAYR_DIR/geoip.dat" | cut -f1)
        local geoip_date=$(stat -c %y "$XRAYR_DIR/geoip.dat" 2>/dev/null | cut -d' ' -f1)
        [ -z "$geoip_date" ] && geoip_date=$(stat -f %Sm -t "%Y-%m-%d" "$XRAYR_DIR/geoip.dat" 2>/dev/null)
        log_info "已存在 geoip.dat (大小: $geoip_size, 修改日期: $geoip_date)"
    else
        log_warning "未找到 geoip.dat 文件"
    fi

    if [ "$geosite_exists" = true ] || [ "$geoip_exists" = true ]; then
        echo ""
        read -p "是否要备份现有文件? (推荐) [Y/n]: " backup_choice
        backup_choice=${backup_choice:-Y}

        if [[ "$backup_choice" =~ ^[Yy]$ ]]; then
            return 0
        else
            return 1
        fi
    fi

    return 1
}

# 备份现有文件
backup_files() {
    local backup_dir="$XRAYR_DIR/backup"
    local timestamp=$(date +%Y%m%d_%H%M%S)

    mkdir -p "$backup_dir"

    log_info "开始备份现有文件..."

    if [ -f "$XRAYR_DIR/geosite.dat" ]; then
        cp "$XRAYR_DIR/geosite.dat" "$backup_dir/geosite.dat.$timestamp"
        log_success "已备份 geosite.dat -> $backup_dir/geosite.dat.$timestamp"
    fi

    if [ -f "$XRAYR_DIR/geoip.dat" ]; then
        cp "$XRAYR_DIR/geoip.dat" "$backup_dir/geoip.dat.$timestamp"
        log_success "已备份 geoip.dat -> $backup_dir/geoip.dat.$timestamp"
    fi
}

# 下载规则文件
download_rules() {
    log_info "开始下载最新规则文件..."

    cd "$XRAYR_DIR" || exit 1

    # 下载 geosite.dat
    log_info "正在下载 geosite.dat (域名分类规则)..."
    if wget -O geosite.dat.tmp "$GEOSITE_URL" 2>&1 | grep -E "保存|saved|Downloaded"; then
        mv geosite.dat.tmp geosite.dat
        log_success "geosite.dat 下载成功"
    else
        log_error "geosite.dat 下载失败"
        rm -f geosite.dat.tmp
        return 1
    fi

    # 下载 geoip.dat
    log_info "正在下载 geoip.dat (IP 分类规则)..."
    if wget -O geoip.dat.tmp "$GEOIP_URL" 2>&1 | grep -E "保存|saved|Downloaded"; then
        mv geoip.dat.tmp geoip.dat
        log_success "geoip.dat 下载成功"
    else
        log_error "geoip.dat 下载失败"
        rm -f geoip.dat.tmp
        return 1
    fi

    return 0
}

# 验证文件完整性
verify_files() {
    log_info "验证下载的文件..."

    local success=true

    if [ -f "$XRAYR_DIR/geosite.dat" ]; then
        local size=$(stat -c%s "$XRAYR_DIR/geosite.dat" 2>/dev/null)
        [ -z "$size" ] && size=$(stat -f%z "$XRAYR_DIR/geosite.dat" 2>/dev/null)

        if [ -n "$size" ] && [ "$size" -gt 100000 ]; then
            log_success "geosite.dat 文件大小正常 ($(du -h "$XRAYR_DIR/geosite.dat" | cut -f1))"
        else
            log_error "geosite.dat 文件大小异常,可能下载不完整"
            success=false
        fi
    else
        log_error "geosite.dat 文件不存在"
        success=false
    fi

    if [ -f "$XRAYR_DIR/geoip.dat" ]; then
        local size=$(stat -c%s "$XRAYR_DIR/geoip.dat" 2>/dev/null)
        [ -z "$size" ] && size=$(stat -f%z "$XRAYR_DIR/geoip.dat" 2>/dev/null)

        if [ -n "$size" ] && [ "$size" -gt 100000 ]; then
            log_success "geoip.dat 文件大小正常 ($(du -h "$XRAYR_DIR/geoip.dat" | cut -f1))"
        else
            log_error "geoip.dat 文件大小异常,可能下载不完整"
            success=false
        fi
    else
        log_error "geoip.dat 文件不存在"
        success=false
    fi

    if [ "$success" = true ]; then
        return 0
    else
        return 1
    fi
}

# 重启 XrayR 服务
restart_xrayr() {
    log_info "准备重启 XrayR 服务..."

    echo ""
    read -p "是否立即重启 XrayR 使新规则生效? [Y/n]: " restart_choice
    restart_choice=${restart_choice:-Y}

    if [[ "$restart_choice" =~ ^[Yy]$ ]]; then
        if command -v XrayR &> /dev/null; then
            log_info "正在重启 XrayR..."
            XrayR restart

            if [ $? -eq 0 ]; then
                log_success "XrayR 重启成功,新规则已生效"
            else
                log_warning "XrayR 重启失败,请手动执行: XrayR restart"
            fi
        elif systemctl is-active --quiet xrayr; then
            log_info "正在重启 XrayR 服务..."
            systemctl restart xrayr

            if [ $? -eq 0 ]; then
                log_success "XrayR 服务重启成功,新规则已生效"
            else
                log_warning "XrayR 服务重启失败,请手动执行: systemctl restart xrayr"
            fi
        else
            log_warning "无法自动重启 XrayR,请手动重启服务使新规则生效"
        fi
    else
        log_info "已跳过重启,请稍后手动重启 XrayR 使新规则生效"
        echo "重启命令: XrayR restart 或 systemctl restart xrayr"
    fi
}

# 显示菜单
show_menu() {
    clear
    echo "======================================"
    echo "      XrayR 路由规则更新工具"
    echo "======================================"
    echo "1. 更新规则文件 (推荐)"
    echo "2. 仅下载不备份"
    echo "3. 查看规则文件信息"
    echo "4. 恢复备份文件"
    echo "0. 退出"
    echo "======================================"
}

# 查看规则文件信息
show_rule_info() {
    clear
    echo "======================================"
    echo "      规则文件信息"
    echo "======================================"

    if [ -f "$XRAYR_DIR/geosite.dat" ]; then
        echo "geosite.dat:"
        echo "  路径: $XRAYR_DIR/geosite.dat"
        echo "  大小: $(du -h "$XRAYR_DIR/geosite.dat" | cut -f1)"
        local date=$(stat -c %y "$XRAYR_DIR/geosite.dat" 2>/dev/null | cut -d' ' -f1)
        [ -z "$date" ] && date=$(stat -f %Sm -t "%Y-%m-%d" "$XRAYR_DIR/geosite.dat" 2>/dev/null)
        echo "  修改时间: $date"
    else
        echo "geosite.dat: 不存在"
    fi

    echo ""

    if [ -f "$XRAYR_DIR/geoip.dat" ]; then
        echo "geoip.dat:"
        echo "  路径: $XRAYR_DIR/geoip.dat"
        echo "  大小: $(du -h "$XRAYR_DIR/geoip.dat" | cut -f1)"
        local date=$(stat -c %y "$XRAYR_DIR/geoip.dat" 2>/dev/null | cut -d' ' -f1)
        [ -z "$date" ] && date=$(stat -f %Sm -t "%Y-%m-%d" "$XRAYR_DIR/geoip.dat" 2>/dev/null)
        echo "  修改时间: $date"
    else
        echo "geoip.dat: 不存在"
    fi

    echo ""
    echo "备份文件列表:"
    if [ -d "$XRAYR_DIR/backup" ]; then
        ls -lh "$XRAYR_DIR/backup" 2>/dev/null | grep -E "geosite|geoip" | awk '{print "  " $9 " (" $5 ", " $6 " " $7 ")"}'
    else
        echo "  无备份文件"
    fi

    echo "======================================"
    read -p "按回车键返回菜单..."
}

# 恢复备份文件
restore_backup() {
    clear
    echo "======================================"
    echo "      恢复备份文件"
    echo "======================================"

    if [ ! -d "$XRAYR_DIR/backup" ]; then
        log_warning "备份目录不存在"
        read -p "按回车键返回菜单..."
        return
    fi

    local backups=$(ls -1 "$XRAYR_DIR/backup" 2>/dev/null | grep -E "geosite|geoip")

    if [ -z "$backups" ]; then
        log_warning "未找到备份文件"
        read -p "按回车键返回菜单..."
        return
    fi

    echo "可用的备份文件:"
    echo "$backups" | nl
    echo ""
    read -p "请输入要恢复的文件编号 (0 返回): " choice

    if [ "$choice" = "0" ]; then
        return
    fi

    local backup_file=$(echo "$backups" | sed -n "${choice}p")

    if [ -z "$backup_file" ]; then
        log_error "无效的选择"
        read -p "按回车键返回菜单..."
        return
    fi

    local target_file=$(echo "$backup_file" | sed 's/\.[0-9_]*$//')

    log_info "准备恢复: $backup_file -> $target_file"
    read -p "确认恢复? [y/N]: " confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        cp "$XRAYR_DIR/backup/$backup_file" "$XRAYR_DIR/$target_file"
        log_success "恢复成功"
        restart_xrayr
    else
        log_info "已取消恢复"
    fi

    read -p "按回车键返回菜单..."
}

# 主函数
main() {
    check_root
    check_dependencies

    if ! check_xrayr; then
        exit 1
    fi

    while true; do
        show_menu
        read -p "请选择操作 [0-4]: " choice

        case $choice in
            1)
                clear
                if check_rule_files; then
                    backup_files
                fi

                if download_rules && verify_files; then
                    log_success "规则文件更新成功!"
                    restart_xrayr
                else
                    log_error "规则文件更新失败"
                fi

                echo ""
                read -p "按回车键继续..."
                ;;
            2)
                clear
                if download_rules && verify_files; then
                    log_success "规则文件下载成功!"
                    restart_xrayr
                else
                    log_error "规则文件下载失败"
                fi

                echo ""
                read -p "按回车键继续..."
                ;;
            3)
                show_rule_info
                ;;
            4)
                restore_backup
                ;;
            0)
                log_info "退出脚本"
                exit 0
                ;;
            *)
                log_error "无效的选择,请重新输入"
                sleep 1
                ;;
        esac
    done
}

# 执行主函数
main
