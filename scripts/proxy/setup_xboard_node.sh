#!/bin/bash
# Xboard-Node 管理入口:安装升级委托官方安装器,绑定变更委托 xbctl。
# 不自动迁移或卸载 V2bX,不覆盖现有节点配置。
UPSTREAM_URL="https://raw.githubusercontent.com/cedar2025/Xboard-Node/dev/install.sh"
XBCTL="/usr/local/bin/xbctl"
CONFIG_FILE="/etc/xboard-node/config.yml"

# 保持与现有 ULS 独立脚本一致的交互风格。
log_info() { printf '[INFO] %s\n' "$1"; }
log_error() { printf '[ERROR] %s\n' "$1" >&2; }

# 返回是否具有现有安装,防止重复安装覆盖配置。
is_installed() {
    [ -e "$CONFIG_FILE" ] || [ -x "$XBCTL" ] || [ -x /usr/local/bin/xboard-node ] || [ -f /etc/systemd/system/xboard-node.service ]
}

# 管理命令只使用官方的固定路径,不执行 PATH 中的同名脚本。
require_xbctl() {
    if [ ! -x "$XBCTL" ]; then
        log_error "未找到 xbctl,请先安装 Xboard-Node 或通过升级修复管理命令"
        return 1
    fi
}

# 询问确认;取消和 EOF 均不执行任何操作。
confirm_action() {
    local answer
    read -r -p "$1 (y/N): " answer || return 1
    [[ "$answer" =~ ^[Yy]$ ]]
}

# 下载至独立临时目录,验证后执行;子 shell 的 EXIT trap 负责全部退出路径清理。
run_installer() (
    local temp_dir
    command -v curl >/dev/null 2>&1 || { log_error "请先安装 curl"; return 1; }
    command -v systemctl >/dev/null 2>&1 || { log_error "官方安装器需要 Linux systemd"; return 1; }
    temp_dir=$(mktemp -d) || return 1
    trap 'rm -rf -- "$temp_dir"' EXIT
    if ! curl -fSL --connect-timeout 15 --max-time 120 "$UPSTREAM_URL" -o "$temp_dir/install.sh"; then
        log_error "官方安装器下载失败,未修改安装"
        return 1
    fi
    if [ ! -s "$temp_dir/install.sh" ] || ! head -n 1 "$temp_dir/install.sh" | grep -q '^#!.*bash' || ! bash -n "$temp_dir/install.sh"; then
        log_error "官方安装器校验失败,未执行"
        return 1
    fi
    bash "$temp_dir/install.sh" "$@"
)

# 仅允许 HTTP(S) 面板地址,不接受空白、凭据或参数形式的输入。
read_panel() {
    read -r -p "面板地址 (https://panel.example.com): " PANEL || return 1
    if [[ ! "$PANEL" =~ ^https?://[^/[:space:]@]+(/[^[:space:]]*)?$ ]]; then
        log_error "请输入有效的 HTTP(S) 面板地址"
        return 1
    fi
    PANEL="${PANEL%/}"
}

# ID 保持字符串传递,避免 Bash 八进制及整数溢出。
read_target() {
    local choice
    read -r -p "绑定类型: 1) 节点  2) 机器 [1]: " choice || return 1
    case "${choice:-1}" in
        1) MODE=node; ID_FLAG=--node-id ;;
        2) MODE=machine; ID_FLAG=--machine-id ;;
        *) log_error "无效绑定类型"; return 1 ;;
    esac
    read -r -p "${MODE} ID: " TARGET_ID || return 1
    if [[ ! "$TARGET_ID" =~ ^[0-9]+$ || ! "$TARGET_ID" =~ [1-9] ]]; then
        log_error "ID 必须是正整数"
        return 1
    fi
}

# 密钥隐藏输入,不打印到 ULS 输出或写入 ULS 缓存。
read_token() {
    read -r -s -p "Token (隐藏输入): " TOKEN || { echo; return 1; }
    echo
    if [ -z "$TOKEN" ]; then
        log_error "Token 不能为空"
        return 1
    fi
}

# 新安装才收集完整配置,已安装时引导使用升级或追加绑定。
install_node() {
    if is_installed; then
        log_error "检测到现有安装,请使用升级或追加绑定;不会重新生成配置"
        return 1
    fi
    local PANEL MODE ID_FLAG TARGET_ID TOKEN kernel_choice kernel
    read_panel && read_target && read_token || return 1
    read -r -p "内核: 1) sing-box  2) Xray [1]: " kernel_choice || return 1
    case "${kernel_choice:-1}" in
        1) kernel=singbox ;;
        2) kernel=xray ;;
        *) log_error "无效内核"; return 1 ;;
    esac
    echo "将安装 Xboard-Node: $PANEL / $MODE $TARGET_ID / $kernel"
    echo "不迁移 V2bX;请自行确认端口不冲突。机器模式需要面板提供相应接口。"
    confirm_action "确认安装?" || return 0
    run_installer install --mode "$MODE" --panel "$PANEL" --token "$TOKEN" "$ID_FLAG" "$TARGET_ID" --kernel "$kernel"
}

# 节点和机器追加都使用 xbctl,不重新运行安装器生成配置。
add_binding() {
    require_xbctl || return 1
    local PANEL MODE ID_FLAG TARGET_ID TOKEN
    read_panel && read_target && read_token || return 1
    confirm_action "确认追加 $MODE $TARGET_ID ($PANEL)?" || return 0
    "$XBCTL" bind "add-$MODE" --panel-url "$PANEL" --token "$TOKEN" "$ID_FLAG" "$TARGET_ID"
}

# 删除仅针对指定面板的指定节点,其他绑定保留。
remove_binding() {
    require_xbctl || return 1
    local PANEL TARGET_ID
    read_panel || return 1
    read -r -p "要删除的节点 ID: " TARGET_ID || return 1
    if [[ ! "$TARGET_ID" =~ ^[0-9]+$ || ! "$TARGET_ID" =~ [1-9] ]]; then
        log_error "ID 必须是正整数"
        return 1
    fi
    confirm_action "确认删除节点 $TARGET_ID ($PANEL) 的绑定?" || return 0
    "$XBCTL" bind remove-node --panel "$PANEL" --node-id "$TARGET_ID"
}

# 升级使用官方专用 action,不传 force-reconfigure。
upgrade_node() {
    is_installed || { log_error "尚未安装 Xboard-Node"; return 1; }
    confirm_action "确认升级程序并重启 Xboard-Node (保留配置)?" || return 0
    run_installer upgrade
}

# 默认卸载保留配置;彻底清理由单独的明确确认控制。
uninstall_node() {
    local purge
    echo "将停止并卸载 Xboard-Node 服务、程序和 xbctl,不影响 V2bX。"
    confirm_action "确认卸载?" || return 0
    read -r -p "是否同时删除 /etc/xboard-node 的配置、密钥及备份? 输入 purge 确认,回车保留: " purge || return 0
    if [ "$purge" = purge ]; then
        run_installer uninstall --purge --yes
    else
        run_installer uninstall --yes
    fi
}

# 返回上层选择器,不因单次操作失败退出整个菜单。
show_menu() {
    local choice result
    while true; do
        echo
        echo "Xboard-Node 管理 (ULS集成版)"
        echo "1) 安装 (仅首次安装)"
        echo "2) 升级程序 (保留配置)"
        echo "3) 查看实例列表"
        echo "4) 查看运行状态"
        echo "5) 追加节点 / 机器绑定"
        echo "6) 删除节点绑定"
        echo "7) 重启服务"
        echo "8) 卸载 (默认保留配置)"
        echo "0) 返回"
        read -r -p "请选择 (0-8): " choice || return 0
        case "$choice" in
            1) install_node ;;
            2) upgrade_node ;;
            3) require_xbctl && "$XBCTL" list ;;
            4) require_xbctl && "$XBCTL" status ;;
            5) add_binding ;;
            6) remove_binding ;;
            7) require_xbctl && { if confirm_action "确认重启 Xboard-Node?"; then "$XBCTL" service restart; fi; } ;;
            8) uninstall_node ;;
            0) return 0 ;;
            *) log_error "无效选择"; continue ;;
        esac
        result=$?
        [ "$result" -eq 0 ] || log_error "操作失败 (退出码: $result),请检查上方输出"
    done
}

# 独立运行入口;允许 source 进行无副作用的模拟测试。
main() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 sudo bash $0 运行"
        return 1
    fi
    show_menu
}

if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
    main "$@"
fi
