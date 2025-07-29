#!/bin/bash

# MLflow备份恢复脚本
# 从备份中恢复MLflow数据

BACKUP_BASE_DIR="/backup"
RESTORE_DIR="/home/feng.hao.jie/test"
BACKUP_NAME="mlflow_backup"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# 列出可用备份
list_backups() {
    log "查找可用备份..."
    
    if [ ! -d "$BACKUP_BASE_DIR" ]; then
        error "备份目录不存在: $BACKUP_BASE_DIR"
        return 1
    fi
    
    cd "$BACKUP_BASE_DIR" || return 1
    
    # 查找备份文件和目录
    local backups=($(find . -maxdepth 1 -name "${BACKUP_NAME}_*" | sort -r))
    
    if [ ${#backups[@]} -eq 0 ]; then
        error "没有找到任何备份文件"
        return 1
    fi
    
    echo -e "${BLUE}可用备份列表:${NC}"
    for i in "${!backups[@]}"; do
        local backup="${backups[$i]}"
        local backup_name=$(basename "$backup")
        local backup_time=""
        
        # 提取时间戳
        if [[ $backup_name =~ ${BACKUP_NAME}_([0-9]{8}_[0-9]{6}) ]]; then
            local timestamp="${BASH_REMATCH[1]}"
            backup_time=$(date -d "${timestamp:0:4}-${timestamp:4:2}-${timestamp:6:2} ${timestamp:9:2}:${timestamp:11:2}:${timestamp:13:2}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "未知时间")
        fi
        
        # 获取文件/目录大小
        local size=""
        if [ -f "$backup" ]; then
            size=$(du -h "$backup" | cut -f1)
            echo "$((i+1))) $backup_name (压缩备份, $size, $backup_time)"
        else
            size=$(du -sh "$backup" | cut -f1)
            echo "$((i+1))) $backup_name (目录备份, $size, $backup_time)"
        fi
    done
    
    echo ""
    read -p "请选择要恢复的备份 [1-${#backups[@]}]: " choice
    
    if [[ $choice -ge 1 && $choice -le ${#backups[@]} ]]; then
        SELECTED_BACKUP="${backups[$((choice-1))]}"
        return 0
    else
        error "无效选择"
        return 1
    fi
}

# 检查恢复目标
check_restore_target() {
    log "检查恢复目标目录: $RESTORE_DIR"
    
    if [ ! -d "$RESTORE_DIR" ]; then
        log "创建恢复目录: $RESTORE_DIR"
        mkdir -p "$RESTORE_DIR"
    fi
    
    # 检查是否有现存数据
    local existing_files=()
    [ -f "$RESTORE_DIR/my.db" ] && existing_files+=("my.db")
    [ -d "$RESTORE_DIR/mlruns" ] && existing_files+=("mlruns")
    [ -d "$RESTORE_DIR/mlartifacts" ] && existing_files+=("mlartifacts")
    
    if [ ${#existing_files[@]} -gt 0 ]; then
        warning "发现现有MLflow数据:"
        for file in "${existing_files[@]}"; do
            warning "  - $RESTORE_DIR/$file"
        done
        
        echo ""
        echo "选择处理方式:"
        echo "1) 备份现有数据后覆盖"
        echo "2) 直接覆盖 (危险!)"
        echo "3) 取消恢复"
        
        read -p "请选择 [1-3]: " backup_choice
        
        case $backup_choice in
            1)
                backup_existing_data
                ;;
            2)
                warning "将直接覆盖现有数据"
                ;;
            3)
                log "用户取消恢复操作"
                exit 0
                ;;
            *)
                error "无效选择"
                exit 1
                ;;
        esac
    fi
}

# 备份现有数据
backup_existing_data() {
    local backup_suffix=$(date '+%Y%m%d_%H%M%S')
    local temp_backup_dir="/tmp/mlflow_backup_before_restore_$backup_suffix"
    
    log "备份现有数据到: $temp_backup_dir"
    mkdir -p "$temp_backup_dir"
    
    [ -f "$RESTORE_DIR/my.db" ] && cp "$RESTORE_DIR/my.db" "$temp_backup_dir/"
    [ -d "$RESTORE_DIR/mlruns" ] && cp -r "$RESTORE_DIR/mlruns" "$temp_backup_dir/"
    [ -d "$RESTORE_DIR/mlartifacts" ] && cp -r "$RESTORE_DIR/mlartifacts" "$temp_backup_dir/"
    
    success "现有数据已备份到: $temp_backup_dir"
}

# 解压备份 (如果需要)
extract_backup() {
    local backup_path="$BACKUP_BASE_DIR/$SELECTED_BACKUP"
    
    if [[ $SELECTED_BACKUP == *.tar.gz ]]; then
        log "解压备份文件: $SELECTED_BACKUP"
        
        local temp_dir="/tmp/mlflow_restore_$$"
        mkdir -p "$temp_dir"
        
        cd "$BACKUP_BASE_DIR" || return 1
        tar -xzf "$SELECTED_BACKUP" -C "$temp_dir"
        
        if [ $? -eq 0 ]; then
            # 找到解压后的目录
            EXTRACTED_BACKUP_DIR=$(find "$temp_dir" -maxdepth 1 -type d -name "${BACKUP_NAME}_*" | head -1)
            if [ -z "$EXTRACTED_BACKUP_DIR" ]; then
                error "无法找到解压后的备份目录"
                return 1
            fi
            success "备份解压完成: $EXTRACTED_BACKUP_DIR"
        else
            error "备份解压失败"
            return 1
        fi
    else
        # 直接使用目录备份
        EXTRACTED_BACKUP_DIR="$backup_path"
        log "使用目录备份: $EXTRACTED_BACKUP_DIR"
    fi
}

# 恢复数据
restore_data() {
    log "开始恢复MLflow数据..."
    
    # 恢复数据库
    if [ -f "$EXTRACTED_BACKUP_DIR/my.db" ]; then
        log "恢复数据库: my.db"
        cp "$EXTRACTED_BACKUP_DIR/my.db" "$RESTORE_DIR/"
        success "数据库恢复完成"
    else
        warning "备份中未找到数据库文件"
    fi
    
    # 恢复mlruns
    if [ -d "$EXTRACTED_BACKUP_DIR/mlruns" ]; then
        log "恢复运行数据: mlruns"
        rm -rf "$RESTORE_DIR/mlruns"
        cp -r "$EXTRACTED_BACKUP_DIR/mlruns" "$RESTORE_DIR/"
        success "运行数据恢复完成"
    else
        warning "备份中未找到mlruns目录"
    fi
    
    # 恢复mlartifacts
    if [ -d "$EXTRACTED_BACKUP_DIR/mlartifacts" ]; then
        log "恢复工件数据: mlartifacts"
        rm -rf "$RESTORE_DIR/mlartifacts"
        cp -r "$EXTRACTED_BACKUP_DIR/mlartifacts" "$RESTORE_DIR/"
        success "工件数据恢复完成"
    else
        warning "备份中未找到mlartifacts目录"
    fi
}

# 验证恢复结果
verify_restore() {
    log "验证恢复结果..."
    
    local issues=()
    
    # 检查数据库
    if [ -f "$RESTORE_DIR/my.db" ]; then
        if command -v sqlite3 >/dev/null 2>&1; then
            local table_count=$(sqlite3 "$RESTORE_DIR/my.db" "SELECT COUNT(*) FROM sqlite_master WHERE type='table';" 2>/dev/null)
            if [ "$table_count" -gt 0 ]; then
                success "数据库验证通过 ($table_count 个表)"
            else
                issues+=("数据库可能损坏")
            fi
        else
            log "SQLite命令不可用，跳过数据库验证"
        fi
    else
        issues+=("数据库文件不存在")
    fi
    
    # 检查目录
    [ ! -d "$RESTORE_DIR/mlruns" ] && issues+=("mlruns目录缺失")
    [ ! -d "$RESTORE_DIR/mlartifacts" ] && issues+=("mlartifacts目录缺失")
    
    if [ ${#issues[@]} -eq 0 ]; then
        success "✅ 所有数据恢复验证通过"
        
        # 显示恢复统计
        echo -e "${BLUE}恢复统计:${NC}"
        [ -f "$RESTORE_DIR/my.db" ] && echo "  数据库: $(du -h "$RESTORE_DIR/my.db" | cut -f1)"
        [ -d "$RESTORE_DIR/mlruns" ] && echo "  运行数据: $(du -sh "$RESTORE_DIR/mlruns" | cut -f1)"
        [ -d "$RESTORE_DIR/mlartifacts" ] && echo "  工件数据: $(du -sh "$RESTORE_DIR/mlartifacts" | cut -f1)"
        
        return 0
    else
        warning "发现以下问题:"
        for issue in "${issues[@]}"; do
            warning "  - $issue"
        done
        return 1
    fi
}

# 清理临时文件
cleanup() {
    if [[ $SELECTED_BACKUP == *.tar.gz ]] && [ -n "$EXTRACTED_BACKUP_DIR" ] && [[ $EXTRACTED_BACKUP_DIR == /tmp/* ]]; then
        log "清理临时文件..."
        rm -rf "$(dirname "$EXTRACTED_BACKUP_DIR")"
    fi
}

# 显示帮助
show_help() {
    cat << EOF
MLflow 备份恢复脚本

用法: $0 [选项]

选项:
  -h, --help           显示此帮助信息
  -l, --list           只列出可用备份
  -d, --backup-dir     指定备份目录 (默认: /backup)
  -r, --restore-dir    指定恢复目录 (默认: /home/feng.hao.jie/test)
  -f, --force          强制恢复，不询问确认

示例:
  $0                   # 交互式恢复
  $0 --list            # 列出可用备份
  $0 --backup-dir /custom/backup  # 使用自定义备份目录

EOF
}

# 主恢复流程
main_restore() {
    log "========== MLflow 备份恢复开始 =========="
    
    # 列出并选择备份
    if ! list_backups; then
        exit 1
    fi
    
    log "选择的备份: $SELECTED_BACKUP"
    
    # 检查恢复目标
    check_restore_target
    
    # 解压备份
    if ! extract_backup; then
        exit 1
    fi
    
    # 恢复数据
    restore_data
    
    # 验证恢复
    verify_restore
    
    # 清理临时文件
    cleanup
    
    success "========== MLflow 备份恢复完成 =========="
    log "数据已恢复到: $RESTORE_DIR"
    log "现在可以启动MLflow服务器进行验证"
}

# 处理命令行参数
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
        -d|--backup-dir)
            BACKUP_BASE_DIR="$2"
            shift 2
            ;;
        -r|--restore-dir)
            RESTORE_DIR="$2"
            shift 2
            ;;
        -f|--force)
            FORCE_RESTORE=true
            shift
            ;;
        *)
            error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done

# 执行主恢复流程
main_restore 