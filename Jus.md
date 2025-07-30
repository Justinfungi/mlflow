# MLflow Docker 部署及备份系统使用指南

## 📋 系统概述

本系统包含3个主要容器，提供完整的MLflow实验跟踪和自动备份解决方案：

1. **PostgreSQL数据库** (`mlflow-postgres`) - 存储MLflow元数据
2. **MLflow服务器** (`mlflow-server`) - 实验跟踪和模型管理
3. **备份服务** (`mlflow-backup-service`) - 自动备份和恢复管理

## 🏗️ 系统架构

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   PostgreSQL    │    │   MLflow Server │    │  Backup Service │
│   (Port 3110)   │◄──►│   (Port 3111)   │◄──►│   (Port 3112)   │
│                 │    │                 │    │                 │
│ • 元数据存储    │    │ • 实验跟踪      │    │ • 自动备份      │
│ • 实验记录      │    │ • 模型管理      │    │ • REST API      │
│ • 用户数据      │    │ • Web界面       │    │ • 恢复管理      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 🚀 快速启动

### 1. 启动所有服务

```bash
# 进入项目目录
cd /home/feng.hao.jie/mlflow

# 构建并启动所有容器
docker-compose up -d

# 查看启动状态
docker-compose ps
```

### 2. 验证服务状态

```bash
# 检查所有容器运行状态
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# 查看服务日志
docker-compose logs -f mlflow
docker-compose logs -f mlflow-backup
```

## 🔧 Docker 管理命令

### 基础操作

```bash
# 启动服务
docker-compose up -d

# 停止服务
docker-compose down

# 重启特定服务
docker-compose restart mlflow
docker-compose restart mlflow-backup

# 查看实时日志
docker-compose logs -f [service_name]

# 进入容器
docker exec -it mlflow-server bash
docker exec -it mlflow-postgres psql -U mlflow_user -d mlflow
docker exec -it mlflow-backup-service bash
```

### 重建和更新

```bash
# 重新构建所有镜像
docker-compose build

# 重新构建特定服务
docker-compose build mlflow
docker-compose build mlflow-backup

# 强制重新构建并启动
docker-compose up -d --build

# 清理未使用的镜像和容器
docker system prune -f
```

### 数据管理

```bash
# 查看Docker卷
docker volume ls

# 备份数据卷
docker run --rm -v mlflow_postgres_data:/data -v $(pwd):/backup alpine tar czf /backup/postgres_backup.tar.gz -C /data .

# 查看卷使用情况
docker system df
```

## 🌐 服务访问

### Web界面

| 服务 | URL | 说明 |
|------|-----|------|
| MLflow Web UI | http://localhost:3111 | 实验跟踪界面 |
| 备份管理API | http://localhost:3112/docs | API文档和测试界面 |
| 备份健康检查 | http://localhost:3112/health | 服务状态检查 |

### 数据库连接

```bash
# 从外部连接PostgreSQL
psql -h localhost -p 3110 -U mlflow_user -d mlflow

# 从容器内连接
docker exec -it mlflow-postgres psql -U mlflow_user -d mlflow
```

## 🔄 备份API使用指南

### 1. 获取备份列表

```bash
# 查看所有可用备份
curl -X GET http://localhost:3112/backups | jq

# 示例响应
[
  {
    "name": "mlflow_backup_20240730_020000.tar.gz",
    "path": "/backup/mlflow/mlflow_backup_20240730_020000.tar.gz",
    "size": "15.2MB",
    "created_at": "2024-07-30T02:00:00",
    "type": "compressed",
    "status": "completed"
  }
]
```

### 2. 创建备份

```bash
# 创建压缩备份（默认）
curl -X POST http://localhost:3112/backups \
  -H "Content-Type: application/json" \
  -d '{"compress": true}'

# 创建非压缩备份并发送邮件通知
curl -X POST http://localhost:3112/backups \
  -H "Content-Type: application/json" \
  -d '{"compress": false, "email": "admin@company.com"}'

# 响应示例
{
  "task_id": "backup_20240730_143000_12345",
  "message": "备份任务已启动",
  "status": "pending"
}
```

### 3. 恢复数据

```bash
# 完整恢复（数据库 + artifacts）
curl -X POST http://localhost:3112/restore \
  -H "Content-Type: application/json" \
  -d '{"backup_name": "mlflow_backup_20240730_020000.tar.gz", "mode": "full"}'

# 仅恢复数据库
curl -X POST http://localhost:3112/restore \
  -H "Content-Type: application/json" \
  -d '{"backup_name": "mlflow_backup_20240730_020000.tar.gz", "mode": "database", "force": true}'

# 仅恢复artifacts
curl -X POST http://localhost:3112/restore \
  -H "Content-Type: application/json" \
  -d '{"backup_name": "mlflow_backup_20240730_020000.tar.gz", "mode": "artifacts"}'
```

### 4. 监控任务状态

```bash
# 获取特定任务状态
curl -X GET http://localhost:3112/tasks/{task_id}

# 获取所有任务
curl -X GET http://localhost:3112/tasks

# 获取运行中的任务
curl -X GET "http://localhost:3112/tasks?status=running"

# 响应示例
{
  "task_id": "backup_20240730_143000_12345",
  "status": "completed",
  "message": "备份成功完成",
  "created_at": "2024-07-30T14:30:00",
  "completed_at": "2024-07-30T14:32:15",
  "result": {
    "stdout": "备份完成，位置: /backup/mlflow/mlflow_backup_20240730_143000.tar.gz",
    "backup_dir": "/backup/mlflow"
  }
}
```

### 5. 下载备份

```bash
# 下载备份文件
curl -X GET http://localhost:3112/backups/mlflow_backup_20240730_020000.tar.gz/download \
  -o backup_20240730.tar.gz
```

### 6. 删除备份

```bash
# 删除指定备份
curl -X DELETE http://localhost:3112/backups/mlflow_backup_20240730_020000.tar.gz
```

### 7. 获取统计信息

```bash
# 查看备份统计
curl -X GET http://localhost:3112/stats | jq

# 示例响应
{
  "backup_count": 7,
  "total_size": 150000000,
  "oldest_backup": "2024-07-23T02:00:00",
  "latest_backup": "2024-07-30T02:00:00",
  "disk_usage": {
    "total": "100G",
    "used": "45G",
    "available": "55G",
    "use_percentage": "45%"
  },
  "task_stats": {
    "total": 15,
    "pending": 0,
    "running": 1,
    "completed": 12,
    "failed": 2
  }
}
```

### 8. 系统管理

```bash
# 清理已完成的任务记录（保留24小时内）
curl -X POST http://localhost:3112/cleanup

# 健康检查
curl -X GET http://localhost:3112/health | jq

# 响应示例
{
  "status": "healthy",
  "checks": {
    "backup_directory": true,
    "backup_script": true,
    "restore_script": true,
    "docker": true
  },
  "timestamp": "2024-07-30T14:30:00"
}
```

## 🛠️ 手动备份恢复

### 手动执行备份

```bash
# 进入备份容器执行完整备份
docker exec mlflow-backup-service /app/backup_services/backup_mlflow.sh

# 创建不压缩的备份
docker exec mlflow-backup-service /app/backup_services/backup_mlflow.sh --no-compress

# 保留14天的备份
docker exec mlflow-backup-service /app/backup_services/backup_mlflow.sh --max-backups 14

# 干运行模式（仅检查）
docker exec mlflow-backup-service /app/backup_services/backup_mlflow.sh --dry-run
```

### 手动执行恢复

```bash
# 列出可用备份
docker exec mlflow-backup-service /app/backup_services/restore_mlflow_backup.sh --list

# 交互式恢复
docker exec -it mlflow-backup-service /app/backup_services/restore_mlflow_backup.sh

# 恢复指定备份
docker exec mlflow-backup-service /app/backup_services/restore_mlflow_backup.sh 1

# 仅恢复数据库
docker exec mlflow-backup-service /app/backup_services/restore_mlflow_backup.sh --database --force 1

# 仅恢复artifacts
docker exec mlflow-backup-service /app/backup_services/restore_mlflow_backup.sh --artifacts 2
```

## ⚙️ 配置说明

### 环境变量

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| BACKUP_DIR | /backup/mlflow | 备份存储目录 |
| BACKUP_API_PORT | 8080 | API服务端口 |
| BACKUP_EMAIL | 无 | 备份通知邮箱 |

### 端口映射

| 容器 | 内部端口 | 外部端口 | 服务 |
|------|----------|----------|------|
| mlflow-postgres | 5432 | 3110 | PostgreSQL数据库 |
| mlflow-server | 5000 | 3111 | MLflow Web界面 |
| mlflow-backup-service | 8080 | 3112 | 备份API服务 |

### 数据卷

| 卷名 | 挂载点 | 说明 |
|------|--------|------|
| postgres_data | /var/lib/postgresql/data | PostgreSQL数据 |
| artifacts_data | /mlflow/artifacts | MLflow工件存储 |
| backup_data | /backup/mlflow | 备份文件存储 |

## 🔧 故障排除

### 常见问题

1. **容器启动失败**
```bash
# 查看详细日志
docker-compose logs mlflow
docker-compose logs mlflow-backup

# 检查端口冲突
netstat -tulpn | grep :3111
```

2. **备份失败**
```bash
# 检查磁盘空间
df -h /backup

# 查看备份容器日志
docker logs mlflow-backup-service

# 检查Docker权限
docker exec mlflow-backup-service docker ps
```

3. **恢复失败**
```bash
# 检查备份文件完整性
docker exec mlflow-backup-service tar -tzf /backup/mlflow/backup_file.tar.gz

# 检查数据库连接
docker exec mlflow-postgres pg_isready -U mlflow_user
```

4. **API服务无响应**
```bash
# 重启备份服务
docker-compose restart mlflow-backup

# 检查API服务状态
curl http://localhost:3112/health
```

## 📅 定时任务

系统自动配置了以下定时任务：

- **每日备份**: 凌晨2点自动执行完整备份
- **保留策略**: 自动保留最近7天的备份，删除过期备份
- **日志记录**: 所有操作都记录到系统日志

查看定时任务状态：
```bash
# 查看cron任务
docker exec mlflow-backup-service crontab -l

# 查看备份日志
docker exec mlflow-backup-service tail -f /var/log/cron/backup.log
```

## 🔒 安全注意事项

1. **访问控制**: 在生产环境中配置防火墙限制API访问
2. **数据加密**: 考虑对备份文件进行加密存储
3. **权限管理**: 定期检查容器和卷的权限设置
4. **网络安全**: 使用Docker网络隔离服务

## 📞 支持联系

如有问题，请检查：
1. 容器日志: `docker-compose logs [service_name]`
2. API健康状态: `curl http://localhost:3112/health`
3. 系统资源: `docker system df`

---

*最后更新: 2024-07-30*