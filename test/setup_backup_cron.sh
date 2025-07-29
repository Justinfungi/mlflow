#!/bin/bash

# MLflow定时备份设置脚本
# 自动配置cron任务进行定期备份

SCRIPT_DIR="/home/feng.hao.jie/test"
BACKUP_SCRIPT="$SCRIPT_DIR/auto_backup_mlflow.sh"
LOG_DIR="$SCRIPT_DIR/backup_logs"

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========== MLflow 定时备份设置 ==========${NC}"

# 创建日志目录
mkdir -p "$LOG_DIR"

# 检查备份脚本是否存在
if [ ! -f "$BACKUP_SCRIPT" ]; then
    echo -e "${YELLOW}错误: 备份脚本不存在: $BACKUP_SCRIPT${NC}"
    exit 1
fi

# 确保脚本有执行权限
chmod +x "$BACKUP_SCRIPT"

echo "选择备份频率:"
echo "1) 每分钟备份 (测试用)"
echo "2) 每天备份 (凌晨2点)"
echo "3) 每周备份 (周日凌晨2点)"
echo "4) 每12小时备份"
echo "5) 自定义时间"
echo "6) 查看现有任务"
echo "7) 删除备份任务"

read -p "请选择 [1-7]: " choice

case $choice in
    1)
        # 每分钟备份
        CRON_SCHEDULE="* * * * *"
        DESCRIPTION="每分钟备份 (测试用)"
        echo -e "${YELLOW}警告: 每分钟备份仅用于测试，生产环境不建议使用${NC}"
        ;;
    2)
        # 每天备份
        CRON_SCHEDULE="0 2 * * *"
        DESCRIPTION="每天凌晨2点备份"
        ;;
    3)
        # 每周备份
        CRON_SCHEDULE="0 2 * * 0"
        DESCRIPTION="每周日凌晨2点备份"
        ;;
    4)
        # 每12小时备份
        CRON_SCHEDULE="0 */12 * * *"
        DESCRIPTION="每12小时备份"
        ;;
    5)
        # 自定义时间
        echo "请输入cron时间格式 (分 时 日 月 周):"
        echo "例如: 0 2 * * * (每天凌晨2点)"
        echo "     30 14 * * 1-5 (工作日下午2:30)"
        read -p "cron时间: " CRON_SCHEDULE
        DESCRIPTION="自定义时间备份"
        ;;
    6)
        # 查看现有任务
        echo -e "${BLUE}当前的备份任务:${NC}"
        crontab -l | grep -E "(mlflow|backup)" || echo "没有找到相关备份任务"
        exit 0
        ;;
    7)
        # 删除备份任务
        echo -e "${YELLOW}删除现有的MLflow备份任务...${NC}"
        crontab -l | grep -v "auto_backup_mlflow.sh" | crontab -
        echo -e "${GREEN}备份任务已删除${NC}"
        exit 0
        ;;
    *)
        echo "无效选择"
        exit 1
        ;;
esac

# 创建完整的cron命令
CRON_COMMAND="$CRON_SCHEDULE $BACKUP_SCRIPT >> $LOG_DIR/backup_\$(date +\%Y\%m).log 2>&1"

# 添加到crontab
echo "添加定时任务..."
(crontab -l 2>/dev/null | grep -v "auto_backup_mlflow.sh"; echo "$CRON_COMMAND") | crontab -

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ 定时备份任务设置成功!${NC}"
    echo -e "${BLUE}任务详情:${NC}"
    echo "  描述: $DESCRIPTION"
    echo "  命令: $BACKUP_SCRIPT"
    echo "  日志: $LOG_DIR/backup_YYYYMM.log"
    echo ""
    echo -e "${BLUE}当前所有定时任务:${NC}"
    crontab -l
    echo ""
    echo -e "${YELLOW}提示:${NC}"
    echo "- 可以运行 'tail -f $LOG_DIR/backup_$(date +%Y%m).log' 查看备份日志"
    echo "- 首次备份将在下次预定时间执行"
    echo "- 如需立即测试，运行: $BACKUP_SCRIPT --dry-run"
else
    echo -e "${YELLOW}❌ 定时任务设置失败${NC}"
    exit 1
fi 