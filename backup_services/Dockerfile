FROM python:3.10-slim

# 安装系统依赖
RUN apt-get update && apt-get install -y \
    cron \
    curl \
    docker.io \
    postgresql-client \
    rsync \
    sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# 创建工作目录
WORKDIR /app

# 复制依赖文件
COPY requirements.txt .

# 安装Python依赖
RUN pip install --no-cache-dir -r requirements.txt

# 复制脚本和API服务
COPY backup_mlflow.sh /app/backup_services/
COPY restore_mlflow_backup.sh /app/backup_services/
COPY backup_api.py /app/backup_services/

# 设置脚本权限
RUN chmod +x /app/backup_services/backup_mlflow.sh
RUN chmod +x /app/backup_services/restore_mlflow_backup.sh

# 创建备份目录
RUN mkdir -p /backup/mlflow

# 创建cron日志目录
RUN mkdir -p /var/log/cron

# 添加定时任务
RUN echo "0 2 * * * root /app/backup_services/backup_mlflow.sh >> /var/log/cron/backup.log 2>&1" > /etc/cron.d/mlflow-backup

# 设置cron权限
RUN chmod 0644 /etc/cron.d/mlflow-backup
RUN crontab /etc/cron.d/mlflow-backup

# 创建启动脚本
RUN echo '#!/bin/bash\n\
# 启动cron服务\n\
service cron start\n\
\n\
# 启动API服务\n\
cd /app/backup_services\n\
python backup_api.py\n\
' > /app/start.sh

RUN chmod +x /app/start.sh

# 暴露API端口
EXPOSE 8080

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# 启动服务
CMD ["/app/start.sh"]