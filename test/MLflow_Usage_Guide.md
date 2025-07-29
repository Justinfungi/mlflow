# MLflow 启动脚本使用指南

## 🚀 可用的启动方式

### 1. SQLite模式 (默认)
最简单的方式，适合开发和测试：
```bash
./start_mlflow_local.sh
# 或者明确指定
./start_mlflow_local.sh sqlite
```

### 2. PostgreSQL模式 (推荐生产环境)
更强大的数据库后端，支持并发和更好的性能：

**步骤1: 启动PostgreSQL容器**
```bash
./start_postgres.sh
```

**步骤2: 启动MLflow服务器**
```bash
./start_mlflow_local.sh postgres
```

## 📋 脚本说明

### `start_mlflow_local.sh`
- **功能**: 启动MLflow服务器
- **参数**: 
  - 无参数或`sqlite`: 使用SQLite数据库
  - `postgres`: 使用PostgreSQL数据库
- **端口**: 3111
- **Web界面**: http://localhost:3111

### `start_postgres.sh`
- **功能**: 启动PostgreSQL Docker容器
- **端口**: 3110 (映射到容器的5432)
- **自动检查**: 容器状态和数据库连接
- **智能管理**: 如果容器已存在则重用

## 🔧 配置参数

### PostgreSQL配置
所有脚本使用相同的配置参数：
```bash
POSTGRES_HOST=localhost
POSTGRES_PORT=3110
POSTGRES_DB=mlflow
POSTGRES_USER=mlflow_user
POSTGRES_PASSWORD=secure_password_123
```

### 环境变量自定义
可以通过环境变量覆盖默认配置：
```bash
export POSTGRES_PORT=5432
export POSTGRES_PASSWORD=mypassword
./start_postgres.sh
./start_mlflow_local.sh postgres
```

## 📊 使用场景对比

| 特性 | SQLite | PostgreSQL |
|------|--------|------------|
| **启动速度** | ⚡ 快速 | 🐌 较慢 |
| **部署复杂度** | 🟢 简单 | 🟡 中等 |
| **并发支持** | 🔴 限制 | 🟢 优秀 |
| **数据完整性** | 🟡 基本 | 🟢 强 |
| **生产适用** | 🔴 不推荐 | 🟢 推荐 |
| **资源占用** | 🟢 低 | 🟡 中等 |

## 🛠️ 常用操作

### 查看运行状态
```bash
# 检查MLflow服务
curl http://localhost:3111/health

# 检查PostgreSQL容器
docker ps | grep mlflow-postgres
```

### 停止服务
```bash
# 停止MLflow服务器 (Ctrl+C)

# 停止PostgreSQL容器
docker stop mlflow-postgres

# 删除PostgreSQL容器 (谨慎!)
docker rm mlflow-postgres
```

### 查看日志
```bash
# PostgreSQL容器日志
docker logs mlflow-postgres

# 如果MLflow启动失败，检查依赖
pip list | grep -E "(mlflow|psycopg2)"
```

## 🧪 测试脚本

启动服务后，可以运行测试脚本验证功能：
```bash
# SQLite模式测试
./start_mlflow_local.sh &
sleep 10
python test_mlflow_local.py

# PostgreSQL模式测试
./start_postgres.sh
./start_mlflow_local.sh postgres &
sleep 15
python test_mlflow_local.py
```

## ⚠️ 故障排除

### PostgreSQL连接失败
1. 检查容器是否运行: `docker ps | grep postgres`
2. 检查端口是否被占用: `netstat -tlnp | grep 3110`
3. 查看容器日志: `docker logs mlflow-postgres`

### MLflow启动失败
1. 检查Python依赖: `pip install mlflow psycopg2-binary`
2. 检查端口占用: `netstat -tlnp | grep 3111`
3. 确认数据库连接: 脚本会自动测试连接

### 权限问题
```bash
chmod +x start_mlflow_local.sh
chmod +x start_postgres.sh
```

---

**更新时间**: 2025-07-29  
**兼容性**: MLflow 3.1.4+, PostgreSQL 13+  
**测试环境**: Linux conda(factor) 