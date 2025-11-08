#!/bin/bash

# 服务器测速工具脚本
# 版本: 1.0
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
}

# 显示菜单
show_menu() {
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}请选择测试工具:${NC}"
    echo
    echo -e "  ${GREEN}1.${NC} NodeQuality测试        - 节点质量综合测试"
    echo -e "  ${GREEN}2.${NC} VPS融合怪服务器测评    - 全方位性能测试"
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

# 主程序循环
main_loop() {
    while true; do
        show_menu

        read -p "请输入选项 (0-2): " choice
        echo

        case $choice in
            1)
                run_nodequality
                ;;
            2)
                run_goecs
                ;;
            0)
                log_info "返回上级菜单"
                exit 0
                ;;
            *)
                log_error "无效选项，请重新选择"
                ;;
        esac

        if [ $choice -ne 0 ]; then
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
