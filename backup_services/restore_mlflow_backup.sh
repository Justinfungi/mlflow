#!/bin/bash

# MLflow恢复脚本
# 从备份中恢复MLflow数据库和artifacts

# ========== 配置参数 ==========
BACKUP_BASE_DIR="${BACKUP_DIR:-/backup/mlflow}"
POSTGRES_CONTAINER="mlflow-postgres"
MLFLOW_CONTAINER="mlflow-server"
RESTORE_MODE="full"  # full, database, artifacts

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
    logger "mlflow-restore: $1"
}

error() {
    echo -e "${RED}[ERROR $(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" >&2
    logger -p user.error "mlflow-restore: ERROR - $1"
}

success() {
    echo -e "${GREEN}[SUCCESS $(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
    logger "mlflow-restore: SUCCESS - $1"
}

warning() {
    echo -e "${YELLOW}[WARNING $(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
    logger -p user.warning "mlflow-restore: WARNING - $1"
}

# 显示可用备份列表
list_backups() {
    log "可用的备份列表:"
    echo "=================================================="
    
    cd "$BACKUP_BASE_DIR" || return 1
    
    local backups=($(find . -maxdepth 1 -name "mlflow_backup_*" -type f -o -name "mlflow_backup_*" -type d | sort -r))
    
    if [ ${#backups[@]} -eq 0 ]; then
        warning "未找到任何备份文件"
        return 1
    fi
    
    local counter=1
    for backup in "${backups[@]}"; do
        local backup_name=$(basename "$backup")
        local backup_date=$(echo "$backup_name" | sed 's/mlflow_backup_//; s/\.tar\.gz$//' | sed 's/_/ /')
        local size
        
        if [[ "$backup" == *.tar.gz ]]; then
            size=$(du -h "$backup" | cut -f1)
            echo "$counter) $backup_name (压缩包, $size) - $backup_date"
        else
            size=$(du -sh "$backup" | cut -f1)
            echo "$counter) $backup_name (目录, $size) - $backup_date"
        fi
        
        counter=$((counter + 1))
    done
    
    echo "=================================================="
    return 0
}

# 选择备份
select_backup() {
    local backup_path="$1"
    
    if [ -n "$backup_path" ]; then
        # 用户指定了备份路径
        if [[ "$backup_path" =~ ^[0-9]+$ ]]; then
            # 用户提供了序号
            cd "$BACKUP_BASE_DIR" || return 1
            local backups=($(find . -maxdepth 1 -name "mlflow_backup_*" -type f -o -name "mlflow_backup_*" -type d | sort -r))
            local index=$((backup_path - 1))
            
            if [ $index -ge 0 ] && [ $index -lt ${#backups[@]} ]; then
                SELECTED_BACKUP="$BACKUP_BASE_DIR/${backups[$index]#./}"
            else
                error "无效的备份序号: $backup_path"
                return 1
            fi
        else
            # 用户提供了完整路径
            SELECTED_BACKUP="$backup_path"
        fi
    else
        # 交互式选择
        list_backups
        echo ""
        read -p "请选择要恢复的备份编号 (或输入完整路径): " choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            cd "$BACKUP_BASE_DIR" || return 1
            local backups=($(find . -maxdepth 1 -name "mlflow_backup_*" -type f -o -name "mlflow_backup_*" -type d | sort -r))
            local index=$((choice - 1))
            
            if [ $index -ge 0 ] && [ $index -lt ${#backups[@]} ]; then
                SELECTED_BACKUP="$BACKUP_BASE_DIR/${backups[$index]#./}"
            else
                error "无效的选择"
                return 1
            fi
        else
            SELECTED_BACKUP="$choice"
        fi
    fi
    
    # 验证备份文件存在
    if [ ! -e "$SELECTED_BACKUP" ]; then
        error "备份文件不存在: $SELECTED_BACKUP"
        return 1
    fi
    
    log "选择的备份: $SELECTED_BACKUP"
    return 0
}

# 准备恢复环境
prepare_restore() {
    log "准备恢复环境..."
    
    # 创建临时目录
    TEMP_DIR=$(mktemp -d)
    export TEMP_DIR
    
    log "临时目录: $TEMP_DIR"
    
    # 解压备份文件 (如果是压缩包)
    if [[ "$SELECTED_BACKUP" == *.tar.gz ]]; then
        log "解压备份文件..."
        tar -xzf "$SELECTED_BACKUP" -C "$TEMP_DIR"
        
        if [ $? -eq 0 ]; then
            # 查找解压后的目录
            BACKUP_CONTENT_DIR=$(find "$TEMP_DIR" -maxdepth 1 -name "mlflow_backup_*" -type d | head -1)
            if [ -z "$BACKUP_CONTENT_DIR" ]; then
                error "解压后未找到备份内容目录"
                return 1
            fi
            success "备份文件解压完成"
        else
            error "解压备份文件失败"
            return 1
        fi
    else
        # 直接使用目录
        BACKUP_CONTENT_DIR="$SELECTED_BACKUP"
    fi
    
    # 验证备份内容
    if [ ! -f "$BACKUP_CONTENT_DIR/backup_info.txt" ]; then
        error "备份文件格式不正确，缺少backup_info.txt"
        return 1
    fi
    
    log "备份信息:"
    cat "$BACKUP_CONTENT_DIR/backup_info.txt"
    echo ""
    
    return 0
}

# 检查容器状态
check_containers() {
    log "检查Docker容器状态..."
    
    local containers=("$POSTGRES_CONTAINER" "$MLFLOW_CONTAINER")
    
    for container in "${containers[@]}"; do
        if ! docker ps --format "table {{.Names}}" | grep -q "^$container$"; then
            error "容器 $container 未运行，请先启动MLflow服务"
            return 1
        else
            log "✅ 容器 $container 正在运行"
        fi
    done
    
    return 0
}

# 停止MLflow服务 (保留数据库)
stop_mlflow_service() {
    if [ "$RESTORE_MODE" = "database" ] || [ "$RESTORE_MODE" = "full" ]; then
        log "停止MLflow服务以进行数据库恢复..."
        docker stop "$MLFLOW_CONTAINER"
        sleep 5
        success "MLflow服务已停止"
    fi
}

# 恢复PostgreSQL数据库
restore_database() {
    local db_backup_file="$BACKUP_CONTENT_DIR/mlflow_db.sql"
    
    if [ ! -f "$db_backup_file" ]; then
        error "数据库备份文件不存在: $db_backup_file"
        return 1
    fi
    
    log "恢复PostgreSQL数据库..."
    warning "这将清除现有的所有MLflow数据！"
    
    if [ "$FORCE_RESTORE" != "true" ]; then
        read -p "确认要继续吗? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log "恢复操作已取消"
            return 1
        fi
    fi
    
    # 清空现有数据库
    log "清空现有数据库..."
    docker exec "$POSTGRES_CONTAINER" psql -U mlflow_user -d mlflow -c "
        DROP SCHEMA public CASCADE;
        CREATE SCHEMA public;
        GRANT ALL ON SCHEMA public TO mlflow_user;
        GRANT ALL ON SCHEMA public TO public;
    "
    
    if [ $? -eq 0 ]; then
        success "现有数据库已清空"
    else
        error "清空数据库失败"
        return 1
    fi
    
    # 恢复数据库
    log "导入备份数据..."
    docker exec -i "$POSTGRES_CONTAINER" psql -U mlflow_user -d mlflow < "$db_backup_file"
    
    if [ $? -eq 0 ]; then
        # 验证恢复结果
        local tables=$(docker exec "$POSTGRES_CONTAINER" psql -U mlflow_user -d mlflow -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';")
        success "数据库恢复完成，共恢复 $(echo $tables | xargs) 个表"
    else
        error "数据库恢复失败"
        return 1
    fi
}

# 恢复Artifacts
restore_artifacts() {
    local artifacts_backup="$BACKUP_CONTENT_DIR/artifacts.tar.gz"
    
    if [ ! -f "$artifacts_backup" ] && [ ! -f "$BACKUP_CONTENT_DIR/artifacts.empty" ]; then
        warning "工件备份文件不存在，跳过工件恢复"
        return 0
    fi
    
    log "恢复MLflow工件存储..."
    
    if [ -f "$BACKUP_CONTENT_DIR/artifacts.empty" ]; then
        log "原始工件目录为空，清空现有工件目录"
        docker exec "$MLFLOW_CONTAINER" find /mlflow/artifacts -mindepth 1 -delete 2>/dev/null
        success "工件目录已清空"
        return 0
    fi
    
    if [ "$FORCE_RESTORE" != "true" ]; then
        read -p "这将替换现有的所有工件，确认要继续吗? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log "工件恢复操作已取消"
            return 0
        fi
    fi
    
    # 清空现有工件目录
    log "清空现有工件目录..."
    docker exec "$MLFLOW_CONTAINER" find /mlflow/artifacts -mindepth 1 -delete 2>/dev/null
    
    # 复制备份文件到容器
    docker cp "$artifacts_backup" "$MLFLOW_CONTAINER:/tmp/artifacts_restore.tar.gz"
    
    # 在容器中解压
    docker exec "$MLFLOW_CONTAINER" tar -xzf /tmp/artifacts_restore.tar.gz -C /mlflow
    
    if [ $? -eq 0 ]; then
        # 清理临时文件
        docker exec "$MLFLOW_CONTAINER" rm -f /tmp/artifacts_restore.tar.gz
        
        # 设置权限
        docker exec "$MLFLOW_CONTAINER" chown -R mlflow:mlflow /mlflow/artifacts
        docker exec "$MLFLOW_CONTAINER" chmod -R 755 /mlflow/artifacts
        
        success "工件恢复完成"
    else
        error "工件恢复失败"
        return 1
    fi
}

# 重启MLflow服务
restart_mlflow_service() {
    if [ "$RESTORE_MODE" = "database" ] || [ "$RESTORE_MODE" = "full" ]; then
        log "重启MLflow服务..."
        docker start "$MLFLOW_CONTAINER"
        
        # 等待服务启动
        log "等待MLflow服务启动..."
        local retry_count=0
        while [ $retry_count -lt 30 ]; do
            if docker logs "$MLFLOW_CONTAINER" --tail 10 2>/dev/null | grep -q "Listening at"; then
                success "MLflow服务已启动"
                return 0
            fi
            sleep 2
            retry_count=$((retry_count + 1))
        done
        
        warning "MLflow服务启动超时，请手动检查"
    fi
}

# 验证恢复结果
verify_restore() {
    log "验证恢复结果..."
    
    # 检查数据库连接
    if [ "$RESTORE_MODE" = "database" ] || [ "$RESTORE_MODE" = "full" ]; then
        local experiments=$(docker exec "$POSTGRES_CONTAINER" psql -U mlflow_user -d mlflow -t -c "SELECT COUNT(*) FROM experiments;" 2>/dev/null | xargs)
        if [ -n "$experiments" ] && [ "$experiments" -ge 0 ]; then
            success "数据库验证通过，共有 $experiments 个实验"
        else
            error "数据库验证失败"
            return 1
        fi
    fi
    
    # 检查工件目录
    if [ "$RESTORE_MODE" = "artifacts" ] || [ "$RESTORE_MODE" = "full" ]; then
        local artifact_count=$(docker exec "$MLFLOW_CONTAINER" find /mlflow/artifacts -type f 2>/dev/null | wc -l)
        success "工件验证通过，共有 $artifact_count 个文件"
    fi
    
    return 0
}

# 清理临时文件
cleanup() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        log "清理临时文件..."
        rm -rf "$TEMP_DIR"
        success "临时文件清理完成"
    fi
}

# 生成恢复报告
generate_restore_report() {
    local report_file="$BACKUP_BASE_DIR/restore_report_$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$report_file" << EOF
MLflow恢复报告
==============
恢复时间: $(date '+%Y-%m-%d %H:%M:%S')
源备份: $SELECTED_BACKUP
恢复模式: $RESTORE_MODE
恢复状态: 成功

恢复内容:
EOF

    if [ "$RESTORE_MODE" = "database" ] || [ "$RESTORE_MODE" = "full" ]; then
        echo "- PostgreSQL数据库: ✅" >> "$report_file"
    fi
    
    if [ "$RESTORE_MODE" = "artifacts" ] || [ "$RESTORE_MODE" = "full" ]; then
        echo "- MLflow工件: ✅" >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF

系统信息:
- 主机: $(hostname)
- 用户: $(whoami)
- 恢复后容器状态:
$(docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(mlflow|postgres)")

注意事项:
- 恢复後请验证数据完整性
- 建议重启相关应用程序
- 检查MLflow Web界面是否正常
EOF

    success "恢复报告生成: $report_file"
}

# 主恢复函数
main_restore() {
    local backup_path="$1"
    
    log "========== MLflow 数据恢复开始 =========="
    
    # 选择备份
    if ! select_backup "$backup_path"; then
        exit 1
    fi
    
    # 准备恢复环境
    if ! prepare_restore; then
        cleanup
        exit 1
    fi
    
    # 检查容器状态
    if ! check_containers; then
        cleanup
        exit 1
    fi
    
    # 根据恢复模式执行不同操作
    case "$RESTORE_MODE" in
        "database")
            stop_mlflow_service
            if restore_database; then
                restart_mlflow_service
                verify_restore
                generate_restore_report
                success "数据库恢复完成"
            else
                error "数据库恢复失败"
                restart_mlflow_service
                cleanup
                exit 1
            fi
            ;;
        "artifacts")
            if restore_artifacts; then
                verify_restore
                generate_restore_report
                success "工件恢复完成"
            else
                error "工件恢复失败"
                cleanup
                exit 1
            fi
            ;;
        "full")
            stop_mlflow_service
            local db_success=false
            local artifacts_success=false
            
            if restore_database; then
                db_success=true
            fi
            
            if restore_artifacts; then
                artifacts_success=true
            fi
            
            restart_mlflow_service
            
            if [ "$db_success" = true ] || [ "$artifacts_success" = true ]; then
                verify_restore
                generate_restore_report
                success "恢复完成 (数据库: $db_success, 工件: $artifacts_success)"
            else
                error "完整恢复失败"
                cleanup
                exit 1
            fi
            ;;
        *)
            error "未知的恢复模式: $RESTORE_MODE"
            cleanup
            exit 1
            ;;
    esac
    
    cleanup
    success "========== MLflow 数据恢复结束 =========="
}

# 显示帮助信息
show_help() {
    cat << EOF
MLflow 数据恢复脚本

用法: $0 [选项] [备份路径或编号]

恢复模式:
  --full              完整恢复 (数据库 + 工件) [默认]
  --database          仅恢复数据库
  --artifacts         仅恢复工件

选项:
  -h, --help          显示此帮助信息
  -l, --list          列出可用备份
  -f, --force         强制恢复，跳过确认提示
  -d, --backup-dir    备份目录 (默认: /backup/mlflow)

示例:
  $0                          # 交互式选择恢复
  $0 1                        # 恢复编号为1的备份
  $0 /backup/mlflow/backup_20240101_120000.tar.gz  # 恢复指定备份文件
  $0 --database --force 1     # 强制恢复编号1的备份中的数据库
  $0 --artifacts 2            # 仅恢复编号2的备份中的工件
  $0 --list                   # 列出可用备份

注意事项:
  - 恢复前请确保MLflow服务正在运行
  - 数据库恢复会清除现有所有数据
  - 建议在恢复前创建当前状态的备份
  - 恢复过程中MLflow服务会暂时停止
EOF
}

# 处理命令行参数
BACKUP_PATH=""
FORCE_RESTORE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -l|--list)
            list_backups
            exit 0
            ;;
        --full)
            RESTORE_MODE="full"
            shift
            ;;
        --database)
            RESTORE_MODE="database"
            shift
            ;;
        --artifacts)
            RESTORE_MODE="artifacts"
            shift
            ;;
        -f|--force)
            FORCE_RESTORE=true
            shift
            ;;
        -d|--backup-dir)
            BACKUP_BASE_DIR="$2"
            shift 2
            ;;
        -*)
            error "未知选项: $1"
            show_help
            exit 1
            ;;
        *)
            BACKUP_PATH="$1"
            shift
            ;;
    esac
done

# 确保以root权限运行或有docker权限
if ! docker ps >/dev/null 2>&1; then
    error "无法连接到Docker，请检查权限或Docker服务状态"
    exit 1
fi

# 检查备份目录
if [ ! -d "$BACKUP_BASE_DIR" ]; then
    error "备份目录不存在: $BACKUP_BASE_DIR"
    exit 1
fi

# 设置清理钩子
trap cleanup EXIT

# 执行恢复
main_restore "$BACKUP_PATH"