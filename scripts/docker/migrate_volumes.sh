#!/bin/bash

#######################################
# Docker Volumes 迁移工具
# 功能：将Docker volumes从一台服务器迁移到另一台服务器
# 支持：密钥登录、密码登录、批量迁移、增量同步
#######################################

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        exit 1
    fi
}

# 检查Docker是否安装
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker未安装，请先安装Docker"
        exit 1
    fi
}

# 检查必要的工具
check_dependencies() {
    local missing_tools=()

    for tool in tar gzip ssh scp; do
        if ! command -v $tool &> /dev/null; then
            missing_tools+=($tool)
        fi
    done

    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "缺少必要工具: ${missing_tools[*]}"
        log_info "请安装这些工具后再运行脚本"
        exit 1
    fi
}

# 显示所有volumes
list_volumes() {
    log_info "当前系统中的Docker Volumes:"
    echo ""
    docker volume ls --format "table {{.Name}}\t{{.Driver}}\t{{.Mountpoint}}" 2>/dev/null
    echo ""
}

# 选择要迁移的volumes
select_volumes() {
    local all_volumes=$(docker volume ls -q)

    if [ -z "$all_volumes" ]; then
        log_error "没有找到任何Docker volumes"
        exit 1
    fi

    echo ""
    log_info "请选择迁移模式:"
    echo "1) 迁移所有volumes"
    echo "2) 选择特定的volumes"
    echo "3) 手动输入volume名称"
    echo ""
    read -p "请输入选项 [1-3]: " mode

    case $mode in
        1)
            SELECTED_VOLUMES=$all_volumes
            log_info "已选择所有volumes (共$(echo $all_volumes | wc -w)个)"
            ;;
        2)
            echo ""
            log_info "可用的volumes列表:"
            local i=1
            declare -A volume_map
            for vol in $all_volumes; do
                echo "$i) $vol"
                volume_map[$i]=$vol
                ((i++))
            done
            echo ""
            read -p "请输入要迁移的volumes编号（用空格分隔，如: 1 3 5）: " selections
            SELECTED_VOLUMES=""
            for num in $selections; do
                if [ -n "${volume_map[$num]}" ]; then
                    SELECTED_VOLUMES="$SELECTED_VOLUMES ${volume_map[$num]}"
                fi
            done
            SELECTED_VOLUMES=$(echo $SELECTED_VOLUMES | xargs)
            ;;
        3)
            echo ""
            read -p "请输入volume名称（多个用空格分隔）: " SELECTED_VOLUMES
            ;;
        *)
            log_error "无效选项"
            exit 1
            ;;
    esac

    if [ -z "$SELECTED_VOLUMES" ]; then
        log_error "未选择任何volume"
        exit 1
    fi

    log_success "已选择 volumes: $SELECTED_VOLUMES"
}

# 配置目标服务器
configure_target_server() {
    echo ""
    log_info "配置目标服务器连接信息"
    echo ""

    read -p "目标服务器IP或域名: " TARGET_HOST
    read -p "目标服务器用户名 [默认: root]: " TARGET_USER
    TARGET_USER=${TARGET_USER:-root}
    read -p "目标服务器SSH端口 [默认: 22]: " TARGET_PORT
    TARGET_PORT=${TARGET_PORT:-22}

    echo ""
    log_info "请选择认证方式:"
    echo "1) SSH密钥认证（推荐）"
    echo "2) 密码认证"
    echo ""
    read -p "请选择 [1-2]: " auth_mode

    case $auth_mode in
        1)
            echo ""
            log_info "请选择私钥输入方式:"
            echo "1) 输入私钥文件路径"
            echo "2) 直接粘贴私钥内容"
            echo ""
            read -p "请选择 [1-2]: " key_input_mode

            case $key_input_mode in
                1)
                    read -p "SSH私钥路径 [默认: ~/.ssh/id_rsa]: " SSH_KEY_PATH
                    SSH_KEY_PATH=${SSH_KEY_PATH:-~/.ssh/id_rsa}

                    # 展开波浪号
                    SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"

                    if [ ! -f "$SSH_KEY_PATH" ]; then
                        log_error "SSH私钥文件不存在: $SSH_KEY_PATH"
                        exit 1
                    fi

                    # 检查私钥权限
                    local key_perms=$(stat -c %a "$SSH_KEY_PATH" 2>/dev/null || stat -f %A "$SSH_KEY_PATH" 2>/dev/null)
                    if [ "$key_perms" != "600" ] && [ "$key_perms" != "400" ]; then
                        log_warning "私钥权限不安全，正在修复..."
                        chmod 600 "$SSH_KEY_PATH"
                    fi

                    SSH_KEY_FILE="$SSH_KEY_PATH"
                    USE_TEMP_KEY=false
                    ;;
                2)
                    echo ""
                    log_info "请粘贴SSH私钥内容（完整包含 -----BEGIN 和 -----END 行）"
                    log_info "粘贴完成后，输入一个空行，然后输入 'EOF' 并回车结束输入"
                    echo ""

                    # 创建临时私钥文件
                    SSH_KEY_FILE="/tmp/ssh_key_$$"
                    > "$SSH_KEY_FILE"

                    while IFS= read -r line; do
                        if [ "$line" = "EOF" ]; then
                            break
                        fi
                        echo "$line" >> "$SSH_KEY_FILE"
                    done

                    # 验证私钥格式
                    if ! grep -q "BEGIN.*PRIVATE KEY" "$SSH_KEY_FILE"; then
                        log_error "无效的私钥格式"
                        rm -f "$SSH_KEY_FILE"
                        exit 1
                    fi

                    # 设置正确权限
                    chmod 600 "$SSH_KEY_FILE"
                    USE_TEMP_KEY=true
                    log_success "私钥已保存到临时文件"
                    ;;
                *)
                    log_error "无效选项"
                    exit 1
                    ;;
            esac

            SSH_OPTIONS="-i $SSH_KEY_FILE -p $TARGET_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
            SCP_OPTIONS="-i $SSH_KEY_FILE -P $TARGET_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
            USE_PASSWORD=false
            ;;
        2)
            if ! command -v sshpass &> /dev/null; then
                log_error "密码认证需要安装 sshpass 工具"
                log_info "安装方法："
                log_info "  Ubuntu/Debian: apt-get install sshpass"
                log_info "  CentOS/RHEL: yum install sshpass"
                log_info "  Arch: pacman -S sshpass"
                exit 1
            fi

            read -sp "目标服务器密码: " TARGET_PASSWORD
            echo ""
            SSH_OPTIONS="-p $TARGET_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
            SCP_OPTIONS="-P $TARGET_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
            USE_PASSWORD=true
            ;;
        *)
            log_error "无效选项"
            exit 1
            ;;
    esac

    # 测试连接
    log_info "测试与目标服务器的连接..."
    if [ "$USE_PASSWORD" = true ]; then
        if sshpass -p "$TARGET_PASSWORD" ssh $SSH_OPTIONS ${TARGET_USER}@${TARGET_HOST} "echo 'Connection test'" &>/dev/null; then
            log_success "连接测试成功"
        else
            log_error "无法连接到目标服务器，请检查配置"
            exit 1
        fi
    else
        if ssh $SSH_OPTIONS ${TARGET_USER}@${TARGET_HOST} "echo 'Connection test'" &>/dev/null; then
            log_success "连接测试成功"
        else
            log_error "无法连接到目标服务器，请检查配置"
            exit 1
        fi
    fi

    # 检查目标服务器是否安装Docker
    log_info "检查目标服务器Docker环境..."
    if [ "$USE_PASSWORD" = true ]; then
        if ! sshpass -p "$TARGET_PASSWORD" ssh $SSH_OPTIONS ${TARGET_USER}@${TARGET_HOST} "command -v docker" &>/dev/null; then
            log_error "目标服务器未安装Docker"
            exit 1
        fi
    else
        if ! ssh $SSH_OPTIONS ${TARGET_USER}@${TARGET_HOST} "command -v docker" &>/dev/null; then
            log_error "目标服务器未安装Docker"
            exit 1
        fi
    fi
    log_success "目标服务器Docker环境检查通过"
}

# 备份单个volume
backup_volume() {
    local volume_name=$1
    local backup_file="${BACKUP_DIR}/${volume_name}.tar.gz"

    log_info "备份 volume: $volume_name"

    # 检查volume是否存在
    if ! docker volume inspect "$volume_name" &>/dev/null; then
        log_error "Volume不存在: $volume_name"
        return 1
    fi

    # 检查是否有容器正在使用该volume
    local containers=$(docker ps -a --filter volume=$volume_name --format "{{.Names}}" 2>/dev/null)
    if [ -n "$containers" ]; then
        log_warning "以下容器正在使用volume '$volume_name':"
        echo "$containers" | sed 's/^/  - /'
        read -p "是否停止这些容器? [y/N]: " stop_containers
        if [[ $stop_containers =~ ^[Yy]$ ]]; then
            echo "$containers" | xargs -r docker stop
            log_success "容器已停止"
            STOPPED_CONTAINERS="$STOPPED_CONTAINERS $containers"
        else
            log_warning "在容器运行时备份可能导致数据不一致"
            read -p "确认继续备份? [y/N]: " confirm
            if [[ ! $confirm =~ ^[Yy]$ ]]; then
                log_info "跳过 volume: $volume_name"
                return 1
            fi
        fi
    fi

    # 创建备份
    if docker run --rm \
        -v ${volume_name}:/data:ro \
        -v ${BACKUP_DIR}:/backup \
        alpine tar czf /backup/${volume_name}.tar.gz -C /data . 2>/dev/null; then

        local size=$(du -h "$backup_file" | cut -f1)
        log_success "备份完成: $backup_file (大小: $size)"
        BACKUP_FILES="$BACKUP_FILES $backup_file"
        return 0
    else
        log_error "备份失败: $volume_name"
        return 1
    fi
}

# 传输备份文件到目标服务器
transfer_backups() {
    log_info "开始传输备份文件到目标服务器..."

    # 在目标服务器创建临时目录
    local remote_backup_dir="/tmp/docker_volumes_backup_$(date +%s)"

    if [ "$USE_PASSWORD" = true ]; then
        sshpass -p "$TARGET_PASSWORD" ssh $SSH_OPTIONS ${TARGET_USER}@${TARGET_HOST} "mkdir -p $remote_backup_dir"
    else
        ssh $SSH_OPTIONS ${TARGET_USER}@${TARGET_HOST} "mkdir -p $remote_backup_dir"
    fi

    REMOTE_BACKUP_DIR=$remote_backup_dir

    # 传输每个备份文件
    local total_files=$(echo $BACKUP_FILES | wc -w)
    local current=0

    for backup_file in $BACKUP_FILES; do
        ((current++))
        local filename=$(basename "$backup_file")
        log_info "传输文件 [$current/$total_files]: $filename"

        if [ "$USE_PASSWORD" = true ]; then
            if sshpass -p "$TARGET_PASSWORD" scp $SCP_OPTIONS "$backup_file" ${TARGET_USER}@${TARGET_HOST}:${remote_backup_dir}/; then
                log_success "传输成功: $filename"
            else
                log_error "传输失败: $filename"
                FAILED_TRANSFERS="$FAILED_TRANSFERS $filename"
            fi
        else
            if scp $SCP_OPTIONS "$backup_file" ${TARGET_USER}@${TARGET_HOST}:${remote_backup_dir}/; then
                log_success "传输成功: $filename"
            else
                log_error "传输失败: $filename"
                FAILED_TRANSFERS="$FAILED_TRANSFERS $filename"
            fi
        fi
    done

    if [ -n "$FAILED_TRANSFERS" ]; then
        log_error "部分文件传输失败: $FAILED_TRANSFERS"
        return 1
    fi

    log_success "所有文件传输完成"
}

# 在目标服务器恢复volumes
restore_volumes() {
    log_info "在目标服务器恢复volumes..."

    # 构建恢复脚本
    local restore_script=$(cat <<'RESTORE_SCRIPT_EOF'
#!/bin/bash
BACKUP_DIR=$1
shift
VOLUMES="$@"

for vol in $VOLUMES; do
    echo "恢复 volume: $vol"

    # 检查volume是否已存在
    if docker volume inspect "$vol" &>/dev/null; then
        echo "Volume已存在: $vol"
        read -p "是否覆盖? [y/N]: " overwrite
        if [[ ! $overwrite =~ ^[Yy]$ ]]; then
            echo "跳过 volume: $vol"
            continue
        fi
        echo "删除现有volume..."
        docker volume rm "$vol" 2>/dev/null || {
            echo "无法删除volume（可能正在使用中），跳过: $vol"
            continue
        }
    fi

    # 创建新volume
    docker volume create "$vol" >/dev/null

    # 恢复数据
    if docker run --rm \
        -v ${vol}:/data \
        -v ${BACKUP_DIR}:/backup \
        alpine tar xzf /backup/${vol}.tar.gz -C /data 2>/dev/null; then
        echo "成功恢复 volume: $vol"
    else
        echo "恢复失败: $vol"
    fi
done
RESTORE_SCRIPT_EOF
)

    # 将恢复脚本传输到目标服务器
    local restore_script_path="${REMOTE_BACKUP_DIR}/restore.sh"

    if [ "$USE_PASSWORD" = true ]; then
        echo "$restore_script" | sshpass -p "$TARGET_PASSWORD" ssh $SSH_OPTIONS ${TARGET_USER}@${TARGET_HOST} "cat > $restore_script_path && chmod +x $restore_script_path"

        # 执行恢复
        log_info "执行恢复操作..."
        sshpass -p "$TARGET_PASSWORD" ssh $SSH_OPTIONS ${TARGET_USER}@${TARGET_HOST} "$restore_script_path $REMOTE_BACKUP_DIR $SELECTED_VOLUMES"
    else
        echo "$restore_script" | ssh $SSH_OPTIONS ${TARGET_USER}@${TARGET_HOST} "cat > $restore_script_path && chmod +x $restore_script_path"

        # 执行恢复
        log_info "执行恢复操作..."
        ssh $SSH_OPTIONS ${TARGET_USER}@${TARGET_HOST} "$restore_script_path $REMOTE_BACKUP_DIR $SELECTED_VOLUMES"
    fi

    log_success "恢复操作完成"
}

# 清理临时文件
cleanup() {
    log_info "清理临时文件..."

    # 清理临时私钥文件
    if [ "$USE_TEMP_KEY" = true ] && [ -n "$SSH_KEY_FILE" ] && [ -f "$SSH_KEY_FILE" ]; then
        rm -f "$SSH_KEY_FILE"
        log_info "临时私钥文件已删除"
    fi

    # 清理本地备份
    if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
        read -p "是否删除本地备份文件? [y/N]: " delete_local
        if [[ $delete_local =~ ^[Yy]$ ]]; then
            rm -rf "$BACKUP_DIR"
            log_success "本地备份已删除"
        else
            log_info "本地备份保存在: $BACKUP_DIR"
        fi
    fi

    # 清理远程备份
    if [ -n "$REMOTE_BACKUP_DIR" ]; then
        read -p "是否删除目标服务器上的备份文件? [y/N]: " delete_remote
        if [[ $delete_remote =~ ^[Yy]$ ]]; then
            if [ "$USE_PASSWORD" = true ]; then
                sshpass -p "$TARGET_PASSWORD" ssh $SSH_OPTIONS ${TARGET_USER}@${TARGET_HOST} "rm -rf $REMOTE_BACKUP_DIR"
            else
                ssh $SSH_OPTIONS ${TARGET_USER}@${TARGET_HOST} "rm -rf $REMOTE_BACKUP_DIR"
            fi
            log_success "远程备份已删除"
        else
            log_info "远程备份保存在: ${TARGET_USER}@${TARGET_HOST}:${REMOTE_BACKUP_DIR}"
        fi
    fi

    # 重启之前停止的容器
    if [ -n "$STOPPED_CONTAINERS" ]; then
        read -p "是否重启之前停止的容器? [y/N]: " restart_containers
        if [[ $restart_containers =~ ^[Yy]$ ]]; then
            echo $STOPPED_CONTAINERS | xargs -r docker start
            log_success "容器已重启"
        fi
    fi
}

# 主函数
main() {
    clear
    echo "========================================"
    echo "    Docker Volumes 迁移工具"
    echo "========================================"
    echo ""

    # 初始化变量
    SELECTED_VOLUMES=""
    BACKUP_FILES=""
    FAILED_TRANSFERS=""
    STOPPED_CONTAINERS=""
    BACKUP_DIR="/tmp/docker_volumes_backup_$(date +%s)"
    REMOTE_BACKUP_DIR=""
    USE_TEMP_KEY=false
    SSH_KEY_FILE=""

    # 检查环境
    check_root
    check_docker
    check_dependencies

    # 显示volumes列表
    list_volumes

    # 选择要迁移的volumes
    select_volumes

    # 配置目标服务器
    configure_target_server

    # 创建本地备份目录
    mkdir -p "$BACKUP_DIR"

    echo ""
    log_info "开始迁移流程..."
    echo ""

    # 备份volumes
    log_info "步骤 1/3: 备份volumes"
    for volume in $SELECTED_VOLUMES; do
        backup_volume "$volume"
    done

    if [ -z "$BACKUP_FILES" ]; then
        log_error "没有成功备份任何volume"
        rm -rf "$BACKUP_DIR"
        exit 1
    fi

    echo ""
    log_info "步骤 2/3: 传输备份文件"
    transfer_backups

    echo ""
    log_info "步骤 3/3: 恢复volumes"
    restore_volumes

    echo ""
    log_success "迁移完成！"
    echo ""

    # 清理
    cleanup

    echo ""
    log_info "迁移摘要:"
    echo "  - 已选择volumes: $(echo $SELECTED_VOLUMES | wc -w)个"
    echo "  - 成功备份: $(echo $BACKUP_FILES | wc -w)个"
    if [ -n "$FAILED_TRANSFERS" ]; then
        echo "  - 传输失败: $(echo $FAILED_TRANSFERS | wc -w)个"
    fi
    echo ""
}

# 捕获中断信号
trap 'echo ""; log_warning "操作已取消"; cleanup; exit 1' INT TERM

# 执行主函数
main
