#!/bin/bash

# MLflow自动备份脚本
# 备份MLflow相关的数据库、运行记录和artifacts到指定目录

# ========== 配置参数 ==========
BACKUP_BASE_DIR="${BACKUP_DIR:-/home/feng.hao.jie/backup}"  # 使用本地backup文件夹
SOURCE_DIR="/home/feng.hao.jie/test"
BACKUP_NAME="mlflow_backup"
MAX_BACKUPS=20  # 1分钟备份需要保留更多
COMPRESS=false  # 1分钟频率不压缩，节省时间

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR $(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS $(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING $(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

# 检查源文件是否存在
check_sources() {
    log "检查备份源文件..."
    
    local sources=(
        "$SOURCE_DIR/my.db"
        "$SOURCE_DIR/mlruns"
        "$SOURCE_DIR/mlartifacts"
    )
    
    local missing_files=()
    
    for source in "${sources[@]}"; do
        if [ ! -e "$source" ]; then
            missing_files+=("$source")
        else
            if [ -f "$source" ]; then
                local size=$(du -h "$source" | cut -f1)
                log "✅ 文件: $source ($size)"
            else
                local size=$(du -sh "$source" 2>/dev/null | cut -f1)
                log "✅ 目录: $source ($size)"
            fi
        fi
    done
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        warning "以下文件/目录不存在，将跳过:"
        for file in "${missing_files[@]}"; do
            warning "  - $file"
        done
    fi
    
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
源目录: $SOURCE_DIR
备份类型: 完整备份
压缩: $COMPRESS
主机: $(hostname)
用户: $(whoami)

备份内容:
- my.db (SQLite数据库)
- mlruns (运行元数据)
- mlartifacts (工件存储)
EOF
    
    return 0
}

# 备份数据库文件
backup_database() {
    log "备份SQLite数据库..."
    
    local source="$SOURCE_DIR/my.db"
    local target="$BACKUP_DIR/my.db"
    
    if [ -f "$source" ]; then
        # 使用SQLite的backup命令确保数据一致性
        if command -v sqlite3 >/dev/null 2>&1; then
            log "使用SQLite BACKUP命令进行一致性备份..."
            sqlite3 "$source" ".backup '$target'"
            if [ $? -eq 0 ]; then
                local size=$(du -h "$target" | cut -f1)
                success "数据库备份完成: $target ($size)"
            else
                error "SQLite备份失败，使用文件复制方式"
                cp "$source" "$target" && success "数据库文件复制完成"
            fi
        else
            log "SQLite命令不可用，使用文件复制方式..."
            cp "$source" "$target" && success "数据库文件复制完成"
        fi
    else
        warning "数据库文件不存在: $source"
    fi
}

# 备份目录
backup_directory() {
    local source_dir="$1"
    local target_name="$2"
    local target="$BACKUP_DIR/$target_name"
    
    if [ -d "$source_dir" ]; then
        log "备份目录: $source_dir -> $target"
        
        # 使用rsync进行高效备份
        if command -v rsync >/dev/null 2>&1; then
            rsync -av --progress "$source_dir/" "$target/"
            if [ $? -eq 0 ]; then
                local size=$(du -sh "$target" | cut -f1)
                success "目录备份完成: $target ($size)"
            else
                error "rsync备份失败，使用cp命令"
                cp -r "$source_dir" "$target" && success "目录复制完成"
            fi
        else
            log "rsync不可用，使用cp命令..."
            cp -r "$source_dir" "$target" && success "目录复制完成"
        fi
    else
        warning "源目录不存在: $source_dir"
    fi
}

# 压缩备份
compress_backup() {
    if [ "$COMPRESS" = true ]; then
        log "压缩备份文件..."
        
        local archive_name="${BACKUP_DIR}.tar.gz"
        
        # 进入备份基目录进行压缩
        cd "$BACKUP_BASE_DIR" || return 1
        
        tar -czf "$archive_name" "$(basename "$BACKUP_DIR")" --progress 2>/dev/null
        
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
    local backups=($(find . -maxdepth 1 -name "${BACKUP_NAME}_*" | sort -r))
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
}

# 生成备份报告
generate_report() {
    local report_file="$BACKUP_BASE_DIR/latest_backup_report.txt"
    
    cat > "$report_file" << EOF
MLflow备份报告
=============
备份时间: $(date '+%Y-%m-%d %H:%M:%S')
备份位置: $BACKUP_DIR
源目录: $SOURCE_DIR

备份内容:
$(cd "$BACKUP_BASE_DIR" && ls -la "$(basename "$BACKUP_DIR")" 2>/dev/null || echo "压缩备份: $(basename "$BACKUP_DIR")")

系统信息:
- 主机: $(hostname)
- 用户: $(whoami)
- 磁盘空间: $(df -h "$BACKUP_BASE_DIR" | tail -1)

最近的备份:
$(cd "$BACKUP_BASE_DIR" && ls -lt ${BACKUP_NAME}_* 2>/dev/null | head -5)
EOF

    success "备份报告生成: $report_file"
}

# 检查磁盘空间
check_disk_space() {
    log "检查磁盘空间..."
    
    local available=$(df "$BACKUP_BASE_DIR" | tail -1 | awk '{print $4}')
    local source_size=$(du -s "$SOURCE_DIR" | awk '{print $1}')
    local required=$((source_size * 2))  # 需要2倍空间以防万一
    
    if [ $available -lt $required ]; then
        error "磁盘空间不足!"
        error "可用空间: $(($available/1024))MB, 需要空间: $(($required/1024))MB"
        return 1
    else
        success "磁盘空间充足: $(($available/1024))MB 可用"
        return 0
    fi
}

# 主备份函数
main_backup() {
    log "========== MLflow 自动备份开始 =========="
    
    # 检查磁盘空间
    if ! check_disk_space; then
        exit 1
    fi
    
    # 检查源文件
    check_sources
    
    # 创建备份目录
    if ! create_backup_dir; then
        exit 1
    fi
    
    # 开始备份
    log "开始备份过程..."
    
    # 备份数据库
    backup_database
    
    # 备份mlruns目录
    backup_directory "$SOURCE_DIR/mlruns" "mlruns"
    
    # 备份mlartifacts目录
    backup_directory "$SOURCE_DIR/mlartifacts" "mlartifacts"
    
    # 压缩备份
    compress_backup
    
    # 清理旧备份
    cleanup_old_backups
    
    # 生成报告
    generate_report
    
    success "========== MLflow 备份完成 =========="
    log "备份位置: $BACKUP_DIR"
}

# 显示帮助信息
show_help() {
    cat << EOF
MLflow 自动备份脚本

用法: $0 [选项]

选项:
  -h, --help          显示此帮助信息
  -c, --compress      启用压缩 (默认: true)
  -n, --no-compress   禁用压缩
  -m, --max-backups N 最大备份数量 (默认: 10)
  -d, --backup-dir    备份目录 (默认: /backup)
  -s, --source-dir    源目录 (默认: /home/feng.hao.jie/test)
  --dry-run          只检查，不执行备份

示例:
  $0                                # 使用默认设置备份
  $0 --no-compress --max-backups 5 # 不压缩，保留5个备份
  $0 --backup-dir /custom/backup    # 自定义备份目录
  $0 --dry-run                      # 检查模式
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
        -s|--source-dir)
            SOURCE_DIR="$2"
            shift 2
            ;;
        --dry-run)
            log "========== 干运行模式 =========="
            check_disk_space
            check_sources
            log "备份将创建在: $BACKUP_BASE_DIR"
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

# 执行主备份流程
main_backup 