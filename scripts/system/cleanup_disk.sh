#!/bin/bash

# 磁盘垃圾清理脚本
# 一站式清理服务器常见垃圾:包管理器缓存、Docker 无用数据、旧临时文件,并定位大文件
# 适用于 apt / yum / dnf / pacman 系发行版;Docker 相关操作在检测到 docker 时才启用
# 设计原则:删除前展示将清理的内容并要求确认,危险操作 (Docker volume) 二次确认,大文件仅列出不删除
# 不使用 set -e:本脚本是常驻菜单循环,单次清理子命令失败不应退出整个工具,错误在各函数内显式处理

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

# 显示根分区磁盘占用概览:总大小 / 已用 / 可用 / 使用率
show_disk_overview() {
    # 从 df 取根分区一行,提取 Size/Used/Avail/Use% 四个关键值
    local line
    line=$(df -h / 2>/dev/null | awk 'NR==2 {print $2, $3, $4, $5}')
    if [ -z "$line" ]; then
        log_warn "无法获取磁盘占用信息"
        return 0
    fi
    read -r total used avail usep <<< "$line"
    echo -e "${BOLD}根分区磁盘占用:${NC} 总 ${BOLD}${total}${NC} | 已用 ${YELLOW}${used}${NC} | 可用 ${GREEN}${avail}${NC} | 使用率 ${BOLD}${usep}${NC}"
}

# 取根分区已用空间 (单位 KB),用于清理前后对比;失败返回 0
get_used_kb() {
    df -kP / 2>/dev/null | awk 'NR==2 {print $3}' || echo 0
}

# 把 KB 数值换算为人类可读字符串 (KB/MB/GB,保留一位小数),纯输出无颜色码
human_kb() {
    awk -v k="$1" 'BEGIN {
        if (k >= 1048576) printf "%.1f GB", k/1048576;
        else if (k >= 1024) printf "%.1f MB", k/1024;
        else printf "%d KB", k;
    }'
}

# 计算清理前后已用空间差值 (KB),负值 (清理期间其他进程写盘) 归零
freed_kb() {
    local freed=$(( $1 - $2 ))
    [ "$freed" -lt 0 ] && freed=0
    echo "$freed"
}

# 报告单项释放量;参数1=清理前KB 参数2=清理后KB
report_freed() {
    local freed
    freed=$(freed_kb "$1" "$2")
    echo -e "${GREEN}↳ 本项释放磁盘空间: ${BOLD}$(human_kb "$freed")${NC}"
}

# 清理包管理器缓存:缓存文件、孤立依赖、旧内核 (仅 apt 自动清理旧内核)
clean_pkg_cache() {
    print_separator
    echo -e "${BOLD}📦 清理包管理器缓存${NC}"
    print_separator

    local pm
    pm=$(detect_pkg_manager)

    if [ "$pm" = "unknown" ]; then
        log_warn "未识别的包管理器,跳过此项"
        return 0
    fi

    log_info "检测到包管理器: $pm"
    echo "将执行以下清理:"
    case "$pm" in
        apt)
            echo "  • apt-get clean        - 清空已下载的 .deb 缓存"
            echo "  • apt-get autoremove   - 移除自动安装且不再需要的依赖 (含旧内核)"
            ;;
        dnf)
            echo "  • dnf clean all        - 清空 dnf 缓存"
            echo "  • dnf autoremove       - 移除不再需要的依赖"
            ;;
        yum)
            echo "  • yum clean all        - 清空 yum 缓存"
            echo "  • yum autoremove       - 移除不再需要的依赖"
            ;;
        pacman)
            echo "  • pacman -Sc           - 清理未安装包的缓存"
            echo "  • 移除孤立包 (pacman -Qtdq)"
            ;;
    esac
    echo
    read -p "是否执行包缓存清理? (Y/n): " choice
    choice=${choice:-Y}
    if [[ ! $choice =~ ^[Yy] ]]; then
        log_info "跳过包缓存清理"
        return 0
    fi

    local used_before
    used_before=$(get_used_kb)

    case "$pm" in
        apt)
            apt-get clean
            apt-get autoremove -y
            ;;
        dnf)
            dnf clean all
            dnf autoremove -y
            ;;
        yum)
            yum clean all
            yum autoremove -y
            ;;
        pacman)
            # 清理未安装包的缓存,保留已安装包的最近版本
            pacman -Sc --noconfirm
            # 移除孤立依赖 (无安装目标时 pacman 会报错,做空值保护)
            local orphans
            orphans=$(pacman -Qtdq 2>/dev/null || true)
            if [ -n "$orphans" ]; then
                echo "$orphans" | pacman -Rns --noconfirm -
            else
                log_info "没有孤立包需要移除"
            fi
            ;;
    esac
    log_success "包缓存清理完成"
    report_freed "$used_before" "$(get_used_kb)"
}

# 清理 Docker 无用数据;named volume 涉及业务数据,默认不清理,需单独确认
clean_docker() {
    print_separator
    echo -e "${BOLD}🐳 清理 Docker 无用数据${NC}"
    print_separator

    if ! command -v docker &>/dev/null; then
        log_info "未检测到 docker,跳过此项"
        return 0
    fi
    if ! docker info &>/dev/null; then
        log_warn "docker 已安装但守护进程未运行,跳过此项"
        return 0
    fi

    echo -e "${BOLD}当前 Docker 磁盘占用:${NC}"
    docker system df 2>/dev/null || log_warn "无法获取 docker 磁盘占用"
    echo

    echo "将清理:停止的容器、悬空(dangling)镜像、未被使用的网络、构建缓存。"
    echo -e "${YELLOW}注意:named volume (数据卷) 默认不清理,避免误删数据库等持久化数据。${NC}"
    echo

    # 记录清理前已用空间,涵盖基础清理 + 数据卷清理两步的总释放
    local used_before did_clean=0
    used_before=$(get_used_kb)

    read -p "是否执行 Docker 基础清理? (Y/n): " choice
    choice=${choice:-Y}
    if [[ $choice =~ ^[Yy] ]]; then
        did_clean=1
        # 不带 --volumes:保留 named volume,只清容器/镜像/网络/构建缓存
        docker system prune -af
        log_success "Docker 基础清理完成"
    else
        log_info "跳过 Docker 基础清理"
    fi

    # 数据卷清理:高风险,单独二次确认
    echo
    local dangling_vol
    dangling_vol=$(docker volume ls -qf dangling=true 2>/dev/null | wc -l)
    if [ "$dangling_vol" -gt 0 ]; then
        log_warn "检测到 $dangling_vol 个未被容器引用的数据卷"
        echo -e "${RED}清理数据卷可能删除尚有用途的数据 (如临时停用的服务),请谨慎确认。${NC}"
        read -p "确认清理未被引用的数据卷? (输入 'yes' 确认): " vol_confirm
        if [ "$vol_confirm" = "yes" ]; then
            docker volume prune -f
            did_clean=1
            log_success "未引用数据卷已清理"
        else
            log_info "保留数据卷"
        fi
    fi

    # 至少执行了一项清理时,报告本轮 Docker 总释放量 (prune 自带输出反映容器视角,这里给磁盘视角)
    if [ "$did_clean" -eq 1 ]; then
        report_freed "$used_before" "$(get_used_kb)"
    fi

    # overlay2 大目录定位:不删除,仅提示
    echo
    echo -e "${BOLD}Docker overlay2 存储层占用 Top 5:${NC}"
    if [ -d /var/lib/docker/overlay2 ]; then
        du -sh /var/lib/docker/overlay2/* 2>/dev/null | sort -rh | head -n 5 \
            || log_info "无法统计 overlay2 目录"
        echo -e "${CYAN}提示:overlay2 大目录通常由镜像层/容器可写层堆积导致;"
        echo -e "完成上面的 prune 后多数会自动回收,仍异常偏大时排查具体容器写入。${NC}"
    else
        log_info "未找到 /var/lib/docker/overlay2 目录"
    fi
}

# 清理旧临时文件:按修改时间清理 /tmp 与 /var/tmp 中较旧的文件,避免误删运行中文件
clean_temp_files() {
    print_separator
    echo -e "${BOLD}🗑️  清理旧临时文件${NC}"
    print_separator

    echo "将清理 /tmp 与 /var/tmp 中较旧的文件 (按修改时间)。"
    echo -e "${YELLOW}为避免删除运行中进程正在使用的临时文件,仅删除超过指定天数未修改的文件。${NC}"
    echo
    read -p "清理多少天前的临时文件? (默认 7,输入 0 跳过): " days
    days=${days:-7}
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        log_error "无效的天数: $days,跳过临时文件清理"
        return 1
    fi
    if [ "$days" -eq 0 ]; then
        log_info "跳过临时文件清理"
        return 0
    fi

    local used_before
    used_before=$(get_used_kb)

    local dir
    for dir in /tmp /var/tmp; do
        [ -d "$dir" ] || continue
        log_info "清理 $dir 中 ${days} 天前的文件..."
        # 删除旧文件,再清理因此变空的目录;忽略无权限/占用项的报错
        find "$dir" -mindepth 1 -type f -mtime +"$days" -delete 2>/dev/null || true
        find "$dir" -mindepth 1 -type d -empty -delete 2>/dev/null || true
    done
    log_success "旧临时文件清理完成"
    report_freed "$used_before" "$(get_used_kb)"
}

# 定位大文件:只读操作,列出占用磁盘最多的目录与文件,供人工判断
locate_large_files() {
    print_separator
    echo -e "${BOLD}🔍 定位大文件/大目录 (仅展示,不删除)${NC}"
    print_separator

    read -p "扫描起始目录 (默认 /): " scan_dir
    scan_dir=${scan_dir:-/}
    if [ ! -d "$scan_dir" ]; then
        log_error "目录不存在: $scan_dir"
        return 1
    fi

    echo
    echo -e "${BOLD}占用最大的 10 个一级子目录 (${scan_dir}):${NC}"
    # --max-depth=1 只看一级,避免在大目录上耗时过久;-x 不跨文件系统
    du -hx --max-depth=1 "$scan_dir" 2>/dev/null | sort -rh | head -n 11 \
        || log_warn "无法统计目录占用"

    echo
    echo -e "${BOLD}占用最大的 10 个文件 (${scan_dir}):${NC}"
    find "$scan_dir" -xdev -type f -printf '%s\t%p\n' 2>/dev/null \
        | sort -rn | head -n 10 \
        | awk -F'\t' '{ printf "%.1f MB\t%s\n", $1/1024/1024, $2 }' \
        || log_warn "无法统计文件占用"

    echo
    log_info "以上仅为展示,请人工核对后再决定是否删除"
}

# 主菜单
show_menu() {
    print_separator
    echo -e "${BOLD}${CYAN}🧹 磁盘垃圾清理工具${NC}"
    print_separator
    show_disk_overview
    echo
    echo "请选择操作:"
    echo "  1) 一键清理 (包缓存 + Docker + 旧临时文件)"
    echo "  2) 仅清理包管理器缓存"
    echo "  3) 仅清理 Docker 无用数据"
    echo "  4) 仅清理旧临时文件"
    echo "  5) 定位大文件/大目录 (只读)"
    echo "  0) 退出"
    echo
}

# 一键清理:依次执行三类清理,完成后展示前后磁盘变化与总释放量
clean_all() {
    echo -e "${BOLD}清理前:${NC}"
    show_disk_overview
    echo
    local used_before
    used_before=$(get_used_kb)

    clean_pkg_cache
    echo
    clean_docker
    echo
    clean_temp_files
    echo
    print_separator
    echo -e "${BOLD}✅ 一键清理完成${NC}"
    print_separator
    echo -e "${BOLD}清理后:${NC}"
    show_disk_overview
    local total_freed
    total_freed=$(freed_kb "$used_before" "$(get_used_kb)")
    echo -e "${GREEN}🎉 本次共释放磁盘空间: ${BOLD}$(human_kb "$total_freed")${NC}"
}

# 主流程
main() {
    while true; do
        show_menu
        read -p "请输入选项 [0-5]: " choice
        echo
        case "$choice" in
            1) clean_all ;;
            2) clean_pkg_cache ;;
            3) clean_docker ;;
            4) clean_temp_files ;;
            5) locate_large_files ;;
            0)
                log_info "退出磁盘清理工具"
                exit 0
                ;;
            *)
                log_warn "无效选项,请重新选择"
                ;;
        esac
        echo
        echo -e "${CYAN}按任意键返回菜单...${NC}"
        read -n 1 -s
        echo
    done
}

main "$@"
