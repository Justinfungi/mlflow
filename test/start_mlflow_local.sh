#!/bin/bash

# MLflow本地服务器启动脚本
# 支持SQLite和PostgreSQL两种后端存储

# 配置选项
DB_TYPE=${1:-"sqlite"}  # 默认使用sqlite，可传参数"postgres"

# PostgreSQL配置（与docker-compose.yml保持一致）
POSTGRES_HOST=${POSTGRES_HOST:-"localhost"}
POSTGRES_PORT=${POSTGRES_PORT:-"3110"}
POSTGRES_DB=${POSTGRES_DB:-"mlflow"}
POSTGRES_USER=${POSTGRES_USER:-"mlflow_user"}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-"secure_password_123"}

echo "🚀 启动MLflow本地服务器..."
echo "========================================"

if [ "$DB_TYPE" = "postgres" ]; then
    # PostgreSQL配置
    BACKEND_STORE_URI="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"
    
    echo "数据库类型: PostgreSQL"
    echo "数据库地址: ${POSTGRES_HOST}:${POSTGRES_PORT}"
    echo "数据库名称: ${POSTGRES_DB}"
    echo "数据库用户: ${POSTGRES_USER}"
    echo ""
    echo "⚠️  请确保PostgreSQL服务器已启动："
    echo "   docker run -d --name mlflow-postgres \\"
    echo "     -e POSTGRES_DB=${POSTGRES_DB} \\"
    echo "     -e POSTGRES_USER=${POSTGRES_USER} \\"
    echo "     -e POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \\"
    echo "     -p ${POSTGRES_PORT}:5432 \\"
    echo "     postgres:13"
    echo ""
    
    # 检查psycopg2是否安装
    if ! python -c "import psycopg2" 2>/dev/null; then
        echo "❌ 缺少psycopg2依赖包，正在安装..."
        pip install psycopg2-binary
    fi
    
    # 测试数据库连接
    echo "🔍 测试数据库连接..."
    if ! python -c "import psycopg2; psycopg2.connect('$BACKEND_STORE_URI')" 2>/dev/null; then
        echo "❌ 无法连接到PostgreSQL数据库"
        echo "请检查数据库是否已启动或配置是否正确"
        exit 1
    fi
    echo "✅ 数据库连接成功"
    
else
    # SQLite配置
    BACKEND_STORE_URI="sqlite:///my.db"
    echo "数据库类型: SQLite"
    echo "数据库文件: my.db"
fi

echo ""
echo "配置信息:"
echo "- 主机: 0.0.0.0"
echo "- 端口: 3111"
echo "- 后端存储: $BACKEND_STORE_URI"
echo "- Artifact存储: ./mlartifacts"
echo "- Web界面: http://localhost:3111"
echo "========================================"
echo ""

# 启动MLflow服务器
mlflow server \
  --host 0.0.0.0 \
  --port 3111 \
  --backend-store-uri "$BACKEND_STORE_URI" \
  --default-artifact-root ./mlartifacts \
  --serve-artifacts 