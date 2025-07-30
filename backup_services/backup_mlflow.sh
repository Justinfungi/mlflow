#!/bin/bash

# MLflow自动备份脚本 - 每日备份版本
# 备份MLflow相关的数据库和artifacts到指定目录

# ========== 配置参数 ==========
BACKUP_BASE_DIR="${BACKUP_DIR:-/backup/mlflow}"
BACKUP_NAME="mlflow_backup"
MAX_BACKUPS=7  # 保留7天的备份
COMPRESS=true  # 启用压缩节省空间
POSTGRES_CONTAINER="mlflow-postgres"
MLFLOW_CONTAINER="mlflow-server"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
    logger "mlflow-backup: $1"
}

error() {
    echo -e "${RED}[ERROR $(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" >&2
    logger -p user.error "mlflow-backup: ERROR - $1"
}

success() {
    echo -e "${GREEN}[SUCCESS $(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
    logger "mlflow-backup: SUCCESS - $1"
}

warning() {
    echo -e "${YELLOW}[WARNING $(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
    logger -p user.warning "mlflow-backup: WARNING - $1"
}

# 检查Docker容器状态
check_containers() {
    log "检查Docker容器状态..."
    
    local containers=("$POSTGRES_CONTAINER" "$MLFLOW_CONTAINER")
    
    for container in "${containers[@]}"; do
        if ! docker ps --format "table {{.Names}}" | grep -q "^$container$"; then
            error "容器 $container 未运行"
            return 1
        else
            log "✅ 容器 $container 正在运行"
        fi
    done
    
    return 0
}

# 创建备份目录
create_backup_dir() {
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    BACKUP_DIR="$BACKUP_BASE_DIR/${BACKUP_NAME}_$timestamp"
    
    log "创建备份目录: $BACKUP_DIR"
    
    if ! mkdir -p "$BACKUP_DIR"; then
        error "无法创建备份目录: $BACKUP_DIR"
        return 1
    fi
    
    # 创建备份信息文件
    cat > "$BACKUP_DIR/backup_info.txt" << EOF
MLflow备份信息
==============
备份时间: $(date '+%Y-%m-%d %H:%M:%S')
备份目录: $BACKUP_DIR
备份类型: 完整备份 (PostgreSQL + Artifacts)
压缩: $COMPRESS
主机: $(hostname)
用户: $(whoami)

备份内容:
- PostgreSQL数据库 (mlflow)
- MLflow工件存储 (/mlflow/artifacts)

容器状态:
$(docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(mlflow|postgres)")
EOF
    
    return 0
}

# 备份PostgreSQL数据库
backup_database() {
    log "备份PostgreSQL数据库..."
    
    local db_backup_file="$BACKUP_DIR/mlflow_db.sql"
    
    # 使用pg_dump备份数据库
    docker exec "$POSTGRES_CONTAINER" pg_dump -U mlflow_user -d mlflow > "$db_backup_file"
    
    if [ $? -eq 0 ] && [ -s "$db_backup_file" ]; then
        local size=$(du -h "$db_backup_file" | cut -f1)
        success "数据库备份完成: $db_backup_file ($size)"
        
        # 验证备份文件内容
        local tables=$(grep -c "CREATE TABLE" "$db_backup_file")
        log "备份包含 $tables 个表"
    else
        error "数据库备份失败"
        return 1
    fi
}

# 备份Artifacts
backup_artifacts() {
    log "备份MLflow工件存储..."
    
    local artifacts_backup="$BACKUP_DIR/artifacts"
    
    # 从容器中复制artifacts目录
    docker exec "$MLFLOW_CONTAINER" tar -czf /tmp/artifacts_backup.tar.gz -C /mlflow artifacts
    
    if [ $? -eq 0 ]; then
        docker cp "$MLFLOW_CONTAINER:/tmp/artifacts_backup.tar.gz" "$artifacts_backup.tar.gz"
        docker exec "$MLFLOW_CONTAINER" rm -f /tmp/artifacts_backup.tar.gz
        
        if [ -f "$artifacts_backup.tar.gz" ]; then
            local size=$(du -h "$artifacts_backup.tar.gz" | cut -f1)
            success "工件备份完成: $artifacts_backup.tar.gz ($size)"
        else
            error "工件备份复制失败"
            return 1
        fi
    else
        warning "工件目录可能为空或备份失败"
        touch "$artifacts_backup.empty"
    fi
}

# 备份Docker卷
backup_volumes() {
    log "备份Docker卷信息..."
    
    # 保存卷信息
    docker volume inspect postgres_data > "$BACKUP_DIR/postgres_volume_info.json" 2>/dev/null
    docker volume inspect artifacts_data > "$BACKUP_DIR/artifacts_volume_info.json" 2>/dev/null
    
    # 保存Compose配置
    if [ -f "/app/docker-compose.yml" ]; then
        cp "/app/docker-compose.yml" "$BACKUP_DIR/docker-compose.yml"
        log "Docker Compose配置已备份"
    fi
}

# 压缩备份
compress_backup() {
    if [ "$COMPRESS" = true ]; then
        log "压缩备份文件..."
        
        local archive_name="${BACKUP_DIR}.tar.gz"
        
        # 进入备份基目录进行压缩
        cd "$BACKUP_BASE_DIR" || return 1
        
        tar -czf "$archive_name" "$(basename "$BACKUP_DIR")" --exclude="*.tar.gz"
        
        if [ $? -eq 0 ]; then
            local original_size=$(du -sh "$BACKUP_DIR" | cut -f1)
            local compressed_size=$(du -h "$archive_name" | cut -f1)
            success "备份压缩完成: $archive_name"
            log "压缩前: $original_size, 压缩后: $compressed_size"
            
            # 删除原始备份目录
            rm -rf "$BACKUP_DIR"
            BACKUP_DIR="$archive_name"
        else
            error "备份压缩失败"
            return 1
        fi
    fi
}

# 清理旧备份
cleanup_old_backups() {
    log "清理旧备份 (保留最近 $MAX_BACKUPS 个)..."
    
    cd "$BACKUP_BASE_DIR" || return 1
    
    # 查找所有备份文件/目录
    local backups=($(find . -maxdepth 1 -name "${BACKUP_NAME}_*" -type f -o -name "${BACKUP_NAME}_*" -type d | sort -r))
    local backup_count=${#backups[@]}
    
    log "发现 $backup_count 个备份"
    
    if [ $backup_count -gt $MAX_BACKUPS ]; then
        local to_delete=$((backup_count - MAX_BACKUPS))
        log "需要删除 $to_delete 个旧备份"
        
        for ((i=MAX_BACKUPS; i<backup_count; i++)); do
            local old_backup="${backups[$i]}"
            log "删除旧备份: $old_backup"
            rm -rf "$old_backup"
        done
        
        success "清理完成，保留了最近 $MAX_BACKUPS 个备份"
    else
        log "备份数量未超过限制，无需清理"
    fi
    
    # 生成备份列表
    log "当前备份列表:"
    ls -lt "$BACKUP_BASE_DIR"/${BACKUP_NAME}_* 2>/dev/null | head -10
}

# 验证备份
verify_backup() {
    log "验证备份完整性..."
    
    local backup_path
    if [ "$COMPRESS" = true ]; then
        backup_path="$BACKUP_DIR"
        # 验证压缩文件
        if tar -tzf "$backup_path" >/dev/null 2>&1; then
            success "压缩文件验证通过"
        else
            error "压缩文件损坏"
            return 1
        fi
    else
        backup_path="$BACKUP_DIR"
        # 验证目录结构
        if [ -f "$backup_path/backup_info.txt" ] && [ -f "$backup_path/mlflow_db.sql" ]; then
            success "备份文件结构验证通过"
        else
            error "备份文件不完整"
            return 1
        fi
    fi
}

# 生成备份报告
generate_report() {
    local report_file="$BACKUP_BASE_DIR/latest_backup_report.txt"
    local backup_size
    
    if [ "$COMPRESS" = true ]; then
        backup_size=$(du -h "$BACKUP_DIR" | cut -f1)
    else
        backup_size=$(du -sh "$BACKUP_DIR" | cut -f1)
    fi
    
    cat > "$report_file" << EOF
MLflow每日备份报告
================
备份时间: $(date '+%Y-%m-%d %H:%M:%S')
备份位置: $BACKUP_DIR
备份大小: $backup_size
备份状态: 成功

系统信息:
- 主机: $(hostname)
- 用户: $(whoami)
- 磁盘空间: $(df -h "$BACKUP_BASE_DIR" | tail -1)

容器状态:
$(docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(mlflow|postgres)")

最近7天备份:
$(cd "$BACKUP_BASE_DIR" && ls -lt ${BACKUP_NAME}_* 2>/dev/null | head -7)

备份保留策略: 保留最近 $MAX_BACKUPS 天
下次备份时间: $(date -d '+1 day' '+%Y-%m-%d %H:%M:%S')
EOF

    success "备份报告生成: $report_file"
    
    # 发送到系统日志
    logger -t mlflow-backup "每日备份完成: $backup_size, 位置: $BACKUP_DIR"
}

# 检查磁盘空间
check_disk_space() {
    log "检查磁盘空间..."
    
    local available=$(df "$BACKUP_BASE_DIR" | tail -1 | awk '{print $4}')
    local min_required=1048576  # 1GB in KB
    
    if [ $available -lt $min_required ]; then
        error "磁盘空间不足!"
        error "可用空间: $(($available/1024))MB, 最少需要: 1GB"
        return 1
    else
        success "磁盘空间充足: $(($available/1024/1024))GB 可用"
        return 0
    fi
}

# 发送通知邮件（可选）
send_notification() {
    local status="$1"
    local message="$2"
    
    # 如果配置了邮件通知
    if command -v mail >/dev/null 2>&1 && [ -n "$BACKUP_EMAIL" ]; then
        echo "$message" | mail -s "MLflow备份$status - $(hostname)" "$BACKUP_EMAIL"
        log "通知邮件已发送到: $BACKUP_EMAIL"
    fi
}

# 主备份函数
main_backup() {
    log "========== MLflow 每日自动备份开始 =========="
    
    local start_time=$(date +%s)
    
    # 检查前置条件
    if ! check_disk_space; then
        send_notification "失败" "磁盘空间不足，备份终止"
        exit 1
    fi
    
    if ! check_containers; then
        send_notification "失败" "Docker容器未正常运行，备份终止"
        exit 1
    fi
    
    # 创建备份目录
    if ! create_backup_dir; then
        send_notification "失败" "无法创建备份目录，备份终止"
        exit 1
    fi
    
    # 执行备份
    log "开始备份过程..."
    
    local backup_success=true
    
    # 备份数据库
    if ! backup_database; then
        backup_success=false
    fi
    
    # 备份工件
    if ! backup_artifacts; then
        warning "工件备份失败，继续执行其他备份"
    fi
    
    # 备份卷信息
    backup_volumes
    
    # 压缩备份
    if [ "$backup_success" = true ]; then
        compress_backup
    fi
    
    # 验证备份
    if ! verify_backup; then
        backup_success=false
    fi
    
    # 清理旧备份
    cleanup_old_backups
    
    # 计算用时
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [ "$backup_success" = true ]; then
        # 生成报告
        generate_report
        
        success "========== MLflow 每日备份完成 =========="
        log "备份位置: $BACKUP_DIR"
        log "备份用时: ${duration}秒"
        
        send_notification "成功" "MLflow每日备份成功完成，用时${duration}秒，位置: $BACKUP_DIR"
    else
        error "========== MLflow 备份失败 =========="
        send_notification "失败" "MLflow每日备份失败，请检查系统状态"
        exit 1
    fi
}

# 显示帮助信息
show_help() {
    cat << EOF
MLflow 每日自动备份脚本

用法: $0 [选项]

选项:
  -h, --help          显示此帮助信息
  -c, --compress      启用压缩 (默认: true)
  -n, --no-compress   禁用压缩
  -m, --max-backups N 最大备份数量 (默认: 7)
  -d, --backup-dir    备份目录 (默认: /backup/mlflow)
  --dry-run          只检查，不执行备份
  --email EMAIL      备份通知邮箱

环境变量:
  BACKUP_DIR         自定义备份目录
  BACKUP_EMAIL       备份通知邮箱

示例:
  $0                                # 使用默认设置备份
  $0 --no-compress --max-backups 14 # 不压缩，保留14天备份
  $0 --email admin@company.com      # 启用邮件通知
  $0 --dry-run                      # 检查模式
  
定时任务设置:
  # 每天凌晨2点执行
  0 2 * * * /path/to/backup_mlflow.sh >/var/log/mlflow-backup.log 2>&1
EOF
}

# 处理命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -c|--compress)
            COMPRESS=true
            shift
            ;;
        -n|--no-compress)
            COMPRESS=false
            shift
            ;;
        -m|--max-backups)
            MAX_BACKUPS="$2"
            shift 2
            ;;
        -d|--backup-dir)
            BACKUP_BASE_DIR="$2"
            shift 2
            ;;
        --email)
            BACKUP_EMAIL="$2"
            shift 2
            ;;
        --dry-run)
            log "========== 干运行模式 =========="
            check_disk_space
            check_containers
            log "备份将创建在: $BACKUP_BASE_DIR"
            log "保留天数: $MAX_BACKUPS"
            log "压缩选项: $COMPRESS"
            log "========== 干运行完成 =========="
            exit 0
            ;;
        *)
            error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done

# 确保以root权限运行或有docker权限
if ! docker ps >/dev/null 2>&1; then
    error "无法连接到Docker，请检查权限或Docker服务状态"
    exit 1
fi

# 创建备份目录
mkdir -p "$BACKUP_BASE_DIR"

# 执行主备份流程
main_backup