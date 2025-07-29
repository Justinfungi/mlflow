# MLflow 本地部署测试环境

## 项目概述

这是一个MLflow本地部署的测试环境，使用SQLite作为后端存储，演示MLflow的核心功能包括实验跟踪、参数记录、指标监控、模型管理和artifact存储。

## 文件架构

```
/home/feng.hao.jie/test/
├── my.db                    # MLflow SQLite数据库 (264K)
├── mlartifacts/            # Artifact存储目录 (56K)
├── mlruns/                 # 运行元数据目录 (4.0K，基本为空)
├── test_mlflow_local.py    # 测试脚本 (8.0K)
└── README.md              # 本文档
```

### 详细目录结构

#### 1. my.db (264K)
- **类型**: SQLite数据库文件
- **用途**: 存储实验元数据、运行信息、参数、指标等
- **内容**:
  - 实验定义和配置
  - 运行记录和状态
  - 参数键值对
  - 指标时间序列数据
  - Artifact路径引用

#### 2. mlartifacts/ (56K)
```
mlartifacts/
└── 1/                              # 实验ID为1
    ├── 5fd98e0a3030475593856f358c661525/   # 运行ID
    │   └── artifacts/
    │       └── reports/
    │           └── test_report.txt         # 测试报告文件
    └── models/                             # 模型存储
        └── m-608a9a7c99f1439e877bfb8016b41097/
            └── artifacts/
                ├── conda.yaml              # Conda环境配置
                ├── MLmodel                 # MLflow模型元数据
                ├── model.pkl               # 序列化的模型文件
                ├── python_env.yaml         # Python环境配置
                └── requirements.txt        # 依赖包列表
```

#### 3. mlruns/ (4.0K)
- **状态**: 基本为空
- **原因**: 使用SQLite后端时，运行元数据存储在数据库中而非文件系统

#### 4. test_mlflow_local.py (8.0K)
- **类型**: Python测试脚本
- **功能**: 全面测试MLflow功能

## MLflow记录的内容

### 📊 实验跟踪 (Experiment Tracking)

| 类型 | 示例内容 | 存储位置 |
|------|----------|----------|
| **实验** | `本地测试实验_1722229126` | my.db |
| **运行** | `本地测试运行` | my.db |
| **运行ID** | `5fd98e0a3030475593856f358c661525` | my.db |

### 🔧 参数记录 (Parameters)

```python
params = {
    "learning_rate": 0.01,
    "batch_size": 32,
    "epochs": 10,
    "model_type": "local_test"
}
```
- **存储**: my.db 中的参数表
- **特点**: 键值对形式，不可变

### 📈 指标记录 (Metrics)

```python
# 模拟5个epoch的训练过程
for epoch in range(5):
    accuracy = 0.7 + epoch * 0.05 + random_noise
    loss = 1.0 - epoch * 0.15 + random_noise
    mlflow.log_metric("accuracy", accuracy, step=epoch)
    mlflow.log_metric("loss", loss, step=epoch)
```
- **存储**: my.db 中的指标表
- **特点**: 时间序列数据，支持step参数

### 💾 数据集记录 (Dataset Logging)

```python
# 记录100行模拟数据
sample_data = pd.DataFrame({
    "feature_1": np.random.randn(100),
    "feature_2": np.random.randn(100), 
    "target": np.random.randint(0, 2, 100)
})

dataset = mlflow.data.from_pandas(
    sample_data,
    source="本地生成的测试数据",
    targets="target"
)
mlflow.log_input(dataset, context="训练数据")
```
- **存储**: 元数据在my.db，数据摘要信息

### 📄 Artifact存储

#### 1. 文本报告
- **文件**: `mlartifacts/1/{run_id}/artifacts/reports/test_report.txt`
- **内容**: 测试报告，包含时间戳、实验信息、测试结果

#### 2. 机器学习模型
- **路径**: `mlartifacts/1/models/m-{model_id}/artifacts/`
- **文件组成**:
  - `model.pkl`: sklearn LogisticRegression模型
  - `MLmodel`: MLflow模型元数据
  - `conda.yaml`: Conda环境规范
  - `python_env.yaml`: Python环境配置  
  - `requirements.txt`: 依赖包列表

## 使用方法

### 1. 启动MLflow服务器
```bash
cd /home/feng.hao.jie/test
mlflow server --port 3111 --backend-store-uri sqlite:///my.db
```

### 2. 运行测试脚本
```bash
python test_mlflow_local.py
```

### 3. 访问Web界面
- URL: http://127.0.0.1:3111
- 功能: 查看实验、比较运行、下载artifacts

## 文件大小总计

| 文件/目录 | 大小 | 说明 |
|-----------|------|------|
| my.db | 264K | SQLite数据库，存储所有元数据 |
| mlartifacts/ | 56K | 模型和文件artifacts |
| mlruns/ | 4.0K | 运行元数据(基本为空) |
| test_mlflow_local.py | 8.0K | 测试脚本 |
| **总计** | **~332K** | 完整测试环境 |

## 特性演示

✅ **实验管理**: 创建和组织机器学习实验  
✅ **参数跟踪**: 记录和比较超参数  
✅ **指标监控**: 跟踪模型性能指标  
✅ **数据集版本**: 记录训练数据信息  
✅ **模型管理**: 保存和版本化模型  
✅ **Artifact存储**: 存储任意文件和报告  
✅ **Web界面**: 可视化实验结果  

## 环境要求

- Python 3.x
- MLflow
- pandas
- numpy  
- scikit-learn
- SQLite (系统内置)

## 注意事项

1. **数据持久性**: 删除my.db会丢失所有实验数据
2. **Artifact存储**: mlartifacts目录包含所有上传的文件
3. **端口配置**: 默认使用3111端口，可根据需要修改
4. **存储后端**: 当前使用SQLite，生产环境建议使用PostgreSQL

---

*最后更新: 2025-07-29*  
*MLflow版本: 3.1.4*  
*环境: Linux conda(factor)* 