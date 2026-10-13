#!/bin/bash

# 服务器测速工具脚本
# 版本: 1.1
# 功能: 提供多种服务器性能测试工具

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        log_info "请使用: sudo $0"
        exit 1
    fi
}

# 显示脚本信息
show_info() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}              服务器测速工具 (ULS集成版)              ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${YELLOW}📊 可用测试工具:${NC}"
    echo
    echo -e "${GREEN}1. NodeQuality测试${NC}"
    echo -e "   - 节点质量综合测试"
    echo -e "   - 测试网络质量、延迟等指标"
    echo -e "   - 适合测试服务器网络性能"
    echo
    echo -e "${GREEN}2. VPS融合怪服务器测评${NC}"
    echo -e "   - 综合性服务器性能测试"
    echo -e "   - CPU、内存、磁盘、网络全方位测试"
    echo -e "   - 适合VPS/云服务器全面评估"
    echo
    echo -e "${GREEN}3. YABS服务器测评${NC}"
    echo -e "   - 查看服务器配置、fio磁盘性能和Geekbench 5/6跑分"
    echo -e "   - 可选完整测试、跳过网络测速或仅配置和跑分"
    echo
}

# 显示菜单
show_menu() {
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}请选择测试工具:${NC}"
    echo
    echo -e "  ${GREEN}1.${NC} NodeQuality测试        - 节点质量综合测试"
    echo -e "  ${GREEN}2.${NC} VPS融合怪服务器测评    - 全方位性能测试"
    echo -e "  ${GREEN}3.${NC} YABS服务器测评         - 配置、磁盘、网络和Geekbench跑分"
    echo
    echo -e "  ${RED}0.${NC} 返回上级菜单"
    echo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
}

# NodeQuality测试
run_nodequality() {
    log_info "正在启动 NodeQuality 测试..."
    echo
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo

    # 执行NodeQuality测试
    bash <(curl -sL https://run.NodeQuality.com)

    echo
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    log_success "NodeQuality 测试完成"
}

# VPS融合怪测试
run_goecs() {
    log_info "正在启动 VPS融合怪 服务器测评..."
    echo
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo

    # 执行VPS融合怪测试
    export noninteractive=true && curl -L https://raw.githubusercontent.com/oneclickvirt/ecs/master/goecs.sh -o goecs.sh && chmod +x goecs.sh && bash goecs.sh env && bash goecs.sh install && goecs

    echo
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    log_success "VPS融合怪测评完成"

    # 清理临时文件
    rm -f goecs.sh
}

# YABS测试：下载校验后执行，子shell退出时清理下载文件
run_yabs() (
    local mode
    local args=()
    local temp_script
    local status

    echo -e "${YELLOW}请选择YABS测试模式:${NC}"
    echo "  1. 跳过网络测速（推荐） - 配置、fio磁盘、Geekbench 6"
    echo "  2. 完整测试             - 配置、磁盘、网络、Geekbench 6"
    echo "  3. 仅配置和Geekbench 6  - 跳过磁盘和网络测速"
    echo "  4. 仅配置和Geekbench 5  - 跳过磁盘、网络测速和GB6"
    echo "  0. 返回测试工具菜单"
    echo
    read -r -p "请输入选项 (0-4，默认1): " mode || return 1

    case "${mode:-1}" in
        1) args=(-i) ;;
        2) args=() ;;
        3) args=(-fi) ;;
        4) args=(-fi5) ;;
        0) return 0 ;;
        *) log_error "无效选项"; return 1 ;;
    esac

    log_warn "测试会占用CPU、内存；完整测试还会消耗较多网络流量"
    if ! command -v curl >/dev/null 2>&1; then
        log_error "curl 未安装，请先安装curl"
        return 1
    fi

    temp_script=$(mktemp "${TMPDIR:-/tmp}/uls-yabs.XXXXXX") || {
        log_error "无法创建YABS临时文件"
        return 1
    }
    trap 'rm -f "$temp_script"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    log_info "正在下载YABS官方脚本..."
    if ! curl -fsSL --connect-timeout 15 --max-time 120 https://yabs.sh -o "$temp_script"; then
        log_error "YABS下载失败"
        return 1
    fi
    if [ ! -s "$temp_script" ] || ! head -n 1 "$temp_script" | grep -q '^#!.*bash' || ! bash -n "$temp_script"; then
        log_error "YABS脚本校验失败，已放弃执行"
        return 1
    fi

    log_info "正在启动YABS服务器测评..."
    bash "$temp_script" "${args[@]}"
    status=$?
    if [ "$status" -eq 0 ]; then
        log_success "YABS脚本运行结束，请查看上方各项测试结果"
    else
        log_error "YABS运行失败或中断（退出码: $status）"
    fi
    return "$status"
)

# 主程序循环
main_loop() {
    while true; do
        show_menu

        read -r -p "请输入选项 (0-3): " choice || return 0
        echo

        case $choice in
            1)
                run_nodequality
                ;;
            2)
                run_goecs
                ;;
            3)
                run_yabs
                ;;
            0)
                log_info "返回上级菜单"
                exit 0
                ;;
            *)
                log_error "无效选项，请重新选择"
                ;;
        esac

        if [ "$choice" != "0" ]; then
            echo
            echo -e "${CYAN}按任意键继续...${NC}"
            read -n 1
            clear
            show_info
        fi
    done
}

# 主函数
main() {
    # 检查权限
    check_root

    # 显示信息
    show_info

    # 启动主循环
    main_loop
}

# 运行主函数
main "$@"
