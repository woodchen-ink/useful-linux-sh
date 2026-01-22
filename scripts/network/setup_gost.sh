#!/bin/bash

# GOST 代理管理脚本
# 功能: 安装、配置和管理 GOST 代理服务
# 支持: HTTP/HTTPS 和 SOCKS5 协议

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 版本配置
GOST_VERSION="2.12.0"
GOST_BINARY="/usr/local/bin/gost"
GOST_SERVICE="/etc/systemd/system/gost.service"
GOST_CONFIG_DIR="/etc/gost"
GOST_CONFIG_FILE="${GOST_CONFIG_DIR}/config.txt"

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
        log_error "此脚本必须以 root 权限运行"
        exit 1
    fi
}

# 检测系统架构
detect_arch() {
    local arch=$(uname -m)
    case $arch in
        x86_64)
            echo "amd64"
            ;;
        aarch64)
            echo "arm64"
            ;;
        *)
            log_error "不支持的系统架构: $arch"
            log_info "支持的架构: x86_64(amd64), aarch64(arm64)"
            exit 1
            ;;
    esac
}

# 检查 GOST 是否已安装
check_gost_installed() {
    if [[ -f "$GOST_BINARY" ]]; then
        return 0
    else
        return 1
    fi
}

# 检查 GOST 服务是否运行
check_gost_running() {
    if systemctl is-active --quiet gost; then
        return 0
    else
        return 1
    fi
}

# 安装 GOST
install_gost() {
    log_info "开始安装 GOST v${GOST_VERSION}..."

    # 检测架构
    local arch=$(detect_arch)
    log_info "检测到系统架构: $arch"

    # 下载链接
    local download_url="https://github.com/ginuerzh/gost/releases/download/v${GOST_VERSION}/gost_${GOST_VERSION}_linux_${arch}.tar.gz"
    local temp_dir=$(mktemp -d)
    local temp_file="${temp_dir}/gost.tar.gz"

    # 下载
    log_info "正在下载 GOST..."
    if ! curl -fsSL "$download_url" -o "$temp_file"; then
        log_error "下载失败,请检查网络连接或版本号"
        rm -rf "$temp_dir"
        exit 1
    fi

    # 解压
    log_info "正在解压文件..."
    tar -xzf "$temp_file" -C "$temp_dir"

    # 安装
    log_info "正在安装到 $GOST_BINARY..."
    mv "${temp_dir}/gost" "$GOST_BINARY"
    chmod +x "$GOST_BINARY"

    # 创建配置目录
    mkdir -p "$GOST_CONFIG_DIR"

    # 清理
    rm -rf "$temp_dir"

    # 验证安装
    if [[ -f "$GOST_BINARY" ]]; then
        local version=$($GOST_BINARY -V 2>&1 | head -n 1)
        log_success "GOST 安装成功!"
        log_info "版本信息: $version"
    else
        log_error "安装失败"
        exit 1
    fi
}

# 配置代理
configure_proxy() {
    log_info "=== GOST 代理配置 ==="
    echo ""

    # 选择协议
    echo -e "${YELLOW}请选择代理协议:${NC}"
    echo "1) HTTP/HTTPS"
    echo "2) SOCKS5"
    read -p "请选择 [1-2]: " protocol_choice

    case $protocol_choice in
        1)
            PROTOCOL="http"
            DEFAULT_PORT="8080"
            ;;
        2)
            PROTOCOL="socks5"
            DEFAULT_PORT="1080"
            ;;
        *)
            log_error "无效的选择"
            exit 1
            ;;
    esac

    # 设置端口
    read -p "请输入监听端口 (默认: $DEFAULT_PORT): " PORT
    PORT=${PORT:-$DEFAULT_PORT}

    # 验证端口
    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
        log_error "无效的端口号: $PORT"
        exit 1
    fi

    # 检查端口是否被占用
    if netstat -tuln 2>/dev/null | grep -q ":$PORT "; then
        log_warning "端口 $PORT 可能已被占用"
        read -p "是否继续? [y/N]: " continue_choice
        if [[ ! "$continue_choice" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    # 是否需要认证
    read -p "是否启用用户认证? [y/N]: " auth_choice

    if [[ "$auth_choice" =~ ^[Yy]$ ]]; then
        read -p "请输入用户名: " USERNAME
        read -s -p "请输入密码: " PASSWORD
        echo ""

        if [[ -z "$USERNAME" ]] || [[ -z "$PASSWORD" ]]; then
            log_error "用户名和密码不能为空"
            exit 1
        fi

        GOST_ARGS="-L=${PROTOCOL}://${USERNAME}:${PASSWORD}@:${PORT}"
    else
        GOST_ARGS="-L=${PROTOCOL}://:${PORT}"
    fi

    # 保存配置
    cat > "$GOST_CONFIG_FILE" <<CONFIG_EOF
# GOST 配置信息
PROTOCOL=$PROTOCOL
PORT=$PORT
USERNAME=${USERNAME:-无}
AUTH_ENABLED=$([[ "$auth_choice" =~ ^[Yy]$ ]] && echo "是" || echo "否")
GOST_ARGS=$GOST_ARGS
CONFIG_TIME=$(date '+%Y-%m-%d %H:%M:%S')
CONFIG_EOF

    log_success "配置保存成功"
}

# 创建 systemd 服务
create_systemd_service() {
    log_info "正在创建 systemd 服务..."

    cat > "$GOST_SERVICE" <<SERVICE_EOF
[Unit]
Description=GOST Proxy Service
Documentation=https://github.com/ginuerzh/gost
After=network.target

[Service]
Type=simple
User=root
ExecStart=${GOST_BINARY} ${GOST_ARGS}
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE_EOF

    # 重载 systemd
    systemctl daemon-reload

    log_success "systemd 服务创建成功"
}

# 启动服务
start_service() {
    log_info "正在启动 GOST 服务..."

    systemctl start gost
    systemctl enable gost

    sleep 2

    if check_gost_running; then
        log_success "GOST 服务启动成功!"
        show_status
    else
        log_error "GOST 服务启动失败"
        log_info "查看日志: journalctl -u gost -n 50"
        exit 1
    fi
}

# 停止服务
stop_service() {
    if check_gost_running; then
        log_info "正在停止 GOST 服务..."
        systemctl stop gost
        systemctl disable gost
        log_success "GOST 服务已停止"
    else
        log_warning "GOST 服务未运行"
    fi
}

# 重启服务
restart_service() {
    log_info "正在重启 GOST 服务..."
    systemctl restart gost
    sleep 2

    if check_gost_running; then
        log_success "GOST 服务重启成功!"
        show_status
    else
        log_error "GOST 服务重启失败"
        log_info "查看日志: journalctl -u gost -n 50"
    fi
}

# 查看状态
show_status() {
    echo ""
    echo -e "${BLUE}=== GOST 服务状态 ===${NC}"

    if check_gost_running; then
        echo -e "运行状态: ${GREEN}运行中${NC}"
    else
        echo -e "运行状态: ${RED}未运行${NC}"
    fi

    if [[ -f "$GOST_CONFIG_FILE" ]]; then
        echo ""
        echo -e "${BLUE}=== 当前配置 ===${NC}"
        cat "$GOST_CONFIG_FILE" | grep -v "^#" | grep -v "^$"
    fi

    echo ""
    if check_gost_running; then
        echo -e "${BLUE}=== 监听端口 ===${NC}"
        netstat -tuln 2>/dev/null | grep -E "$(grep "^PORT=" "$GOST_CONFIG_FILE" 2>/dev/null | cut -d= -f2)" || echo "无法获取端口信息"

        echo ""
        echo -e "${BLUE}=== 进程信息 ===${NC}"
        ps aux | grep "[g]ost" | awk '{print "PID: "$2", CPU: "$3"%, MEM: "$4"%"}'
    fi

    echo ""
}

# 查看日志
show_logs() {
    if [[ -f "$GOST_SERVICE" ]]; then
        log_info "显示最近 50 条日志..."
        journalctl -u gost -n 50 --no-pager
    else
        log_warning "GOST 服务未安装"
    fi
}

# 卸载 GOST
uninstall_gost() {
    log_warning "即将卸载 GOST 及其所有配置"
    read -p "确认卸载? [y/N]: " confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "取消卸载"
        return
    fi

    # 停止服务
    if check_gost_running; then
        systemctl stop gost
    fi

    # 禁用服务
    if [[ -f "$GOST_SERVICE" ]]; then
        systemctl disable gost 2>/dev/null || true
        rm -f "$GOST_SERVICE"
        systemctl daemon-reload
    fi

    # 删除二进制文件
    rm -f "$GOST_BINARY"

    # 删除配置目录
    rm -rf "$GOST_CONFIG_DIR"

    log_success "GOST 已完全卸载"
}

# 主菜单
show_menu() {
    clear
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}    GOST 代理管理工具${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""

    if check_gost_installed; then
        echo -e "安装状态: ${GREEN}已安装${NC}"
    else
        echo -e "安装状态: ${RED}未安装${NC}"
    fi

    if check_gost_running; then
        echo -e "运行状态: ${GREEN}运行中${NC}"
    else
        echo -e "运行状态: ${YELLOW}未运行${NC}"
    fi

    echo ""
    echo "1) 安装/更新 GOST"
    echo "2) 配置并启动代理"
    echo "3) 停止代理"
    echo "4) 重启代理"
    echo "5) 查看状态"
    echo "6) 查看日志"
    echo "7) 卸载 GOST"
    echo "0) 退出"
    echo ""
}

# 主函数
main() {
    check_root

    while true; do
        show_menu
        read -p "请选择操作 [0-7]: " choice

        case $choice in
            1)
                install_gost
                read -p "按回车键继续..."
                ;;
            2)
                if ! check_gost_installed; then
                    log_error "请先安装 GOST"
                    read -p "按回车键继续..."
                    continue
                fi

                if check_gost_running; then
                    log_warning "GOST 服务正在运行"
                    read -p "是否停止当前服务并重新配置? [y/N]: " reconfig
                    if [[ "$reconfig" =~ ^[Yy]$ ]]; then
                        stop_service
                    else
                        read -p "按回车键继续..."
                        continue
                    fi
                fi

                configure_proxy
                create_systemd_service
                start_service
                read -p "按回车键继续..."
                ;;
            3)
                stop_service
                read -p "按回车键继续..."
                ;;
            4)
                if ! check_gost_installed; then
                    log_error "请先安装 GOST"
                    read -p "按回车键继续..."
                    continue
                fi
                restart_service
                read -p "按回车键继续..."
                ;;
            5)
                show_status
                read -p "按回车键继续..."
                ;;
            6)
                show_logs
                read -p "按回车键继续..."
                ;;
            7)
                uninstall_gost
                read -p "按回车键继续..."
                ;;
            0)
                log_info "退出程序"
                exit 0
                ;;
            *)
                log_error "无效的选择"
                read -p "按回车键继续..."
                ;;
        esac
    done
}

# 执行主函数
main
