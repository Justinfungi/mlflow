#!/bin/bash

# PostgreSQL容器启动脚本
# 与MLflow配置保持一致

# 配置参数（与docker-compose.yml和start_mlflow_local.sh保持一致）
CONTAINER_NAME="mlflow-postgres"
POSTGRES_DB="mlflow"
POSTGRES_USER="mlflow_user"
POSTGRES_PASSWORD="secure_password_123"
POSTGRES_PORT="3110"

echo "🐘 启动PostgreSQL容器..."
echo "========================================"
echo "容器名称: ${CONTAINER_NAME}"
echo "数据库名: ${POSTGRES_DB}"
echo "用户名: ${POSTGRES_USER}"
echo "端口: ${POSTGRES_PORT}"
echo "========================================"

# 检查容器是否已存在
if docker ps -a --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo "📋 发现已存在的容器 ${CONTAINER_NAME}"
    
    # 检查容器状态
    if docker ps --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        echo "✅ 容器已在运行"
        echo "💡 连接信息:"
        echo "   Host: localhost"
        echo "   Port: ${POSTGRES_PORT}"
        echo "   Database: ${POSTGRES_DB}"
        echo "   Username: ${POSTGRES_USER}"
        echo "   Password: ${POSTGRES_PASSWORD}"
        exit 0
    else
        echo "🔄 启动已存在的容器..."
        docker start ${CONTAINER_NAME}
    fi
else
    echo "🚀 创建并启动新容器..."
    docker run -d \
        --name ${CONTAINER_NAME} \
        -e POSTGRES_DB=${POSTGRES_DB} \
        -e POSTGRES_USER=${POSTGRES_USER} \
        -e POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \
        -p ${POSTGRES_PORT}:5432 \
        postgres:13
fi

# 等待数据库启动
echo "⏳ 等待数据库启动..."
sleep 5

# 测试连接
echo "🔍 测试数据库连接..."
for i in {1..10}; do
    if docker exec ${CONTAINER_NAME} pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB} > /dev/null 2>&1; then
        echo "✅ PostgreSQL已准备就绪！"
        echo ""
        echo "💡 连接信息:"
        echo "   Host: localhost"
        echo "   Port: ${POSTGRES_PORT}"
        echo "   Database: ${POSTGRES_DB}"
        echo "   Username: ${POSTGRES_USER}"
        echo "   Password: ${POSTGRES_PASSWORD}"
        echo ""
        echo "🚀 现在可以运行: ./start_mlflow_local.sh postgres"
        exit 0
    fi
    echo "   等待中... ($i/10)"
    sleep 2
done

echo "❌ 数据库启动超时，请检查Docker状态"
docker logs ${CONTAINER_NAME} --tail 10
exit 1 