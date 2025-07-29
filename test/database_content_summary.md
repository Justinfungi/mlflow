# MLflow SQLite数据库内容总结
**数据库文件**: `/home/feng.hao.jie/test/my.db` (264K)  
**查看时间**: 2025-07-29

## 📊 数据库结构概览

### 核心表统计
| 表名 | 记录数 | 主要内容 |
|------|--------|----------|
| `experiments` | 2 | 实验定义 |
| `runs` | 1 | 运行记录 |
| `params` | 4 | 超参数 |
| `metrics` | 10 | 性能指标 |
| `datasets` | 1 | 数据集信息 |
| `registered_models` | 1 | 注册模型 |
| `model_versions` | 1 | 模型版本 |
| `inputs` | 2 | 输入关联 |

## 🧪 实验记录 (experiments)

| ID | 名称 | 状态 | Artifact位置 |
|----|------|------|-------------|
| 0 | Default | active | mlflow-artifacts:/0 |
| 1 | 本地测试实验_1753767493 | active | mlflow-artifacts:/1 |

**创建时间**: 2025-07-29 13:38 (Unix: 1753767494145)

## 🏃 运行记录 (runs)

| 运行ID | 实验ID | 名称 | 状态 | 开始时间 | 结束时间 |
|--------|--------|------|------|----------|----------|
| `5fd98e0a...` | 1 | 本地测试运行 | FINISHED | 13:38:14 | 13:38:18 |

**运行时长**: 约4.7秒  
**完整运行ID**: `5fd98e0a3030475593856f358c661525`

## 🔧 参数记录 (params)

| 参数名 | 值 | 运行ID |
|--------|----|----|
| learning_rate | 0.01 | 5fd98e0a... |
| batch_size | 32 | 5fd98e0a... |
| epochs | 10 | 5fd98e0a... |
| model_type | local_test | 5fd98e0a... |

## 📈 指标记录 (metrics)

### Accuracy变化 (5个epoch)
| Step | Accuracy | Loss |
|------|----------|-------|
| 0 | 0.7039 | 1.0185 |
| 1 | 0.7303 | 0.9437 |
| 2 | 0.7505 | 0.6451 |
| 3 | 0.8704 | 0.5398 |
| 4 | 0.8989 | 0.4350 |

**趋势**: 准确率从70.39%提升到89.89%，损失从1.018降低到0.435

## 💾 数据集记录 (datasets)

| 数据集ID | 类型 | 来源 | 结构 |
|----------|------|------|------|
| 3ca2eb86... | dataset | 本地生成的测试数据 | 100行×3列 |

**列结构**:
- `feature_1`: double (required)
- `feature_2`: double (required)  
- `target`: long (required)

**数据统计**: 100行，300个数据元素

## 🤖 模型管理

### 注册模型 (registered_models)
| 模型名 | 创建时间 | 最后更新 | 描述 |
|--------|----------|----------|------|
| 本地测试模型 | 13:38:18 | 13:38:18 | (空) |

### 模型版本 (model_versions)
| 模型名 | 版本 | 状态 | 运行ID | Artifact路径 |
|--------|------|------|--------|-------------|
| 本地测试模型 | 1 | READY | 5fd98e0a... | mlflow-artifacts:/1/models/m-608a9a7c.../artifacts |

**模型URI**: `models:/m-608a9a7c99f1439e877bfb8016b41097`

## 🔗 输入关联 (inputs)

| 输入ID | 类型 | 目标ID | 关系类型 | 关联对象 |
|--------|------|--------|----------|----------|
| de393419... | DATASET | 3ca2eb86... | RUN | 5fd98e0a... |
| 4e1b56f3... | RUN_OUTPUT | 5fd98e0a... | MODEL_OUTPUT | m-608a9a... |

## 🗂️ 完整数据库表列表

**核心功能表**:
- `experiments` - 实验定义
- `runs` - 运行记录  
- `params` - 参数存储
- `metrics` - 指标数据
- `datasets` - 数据集元数据
- `inputs` - 输入关联

**模型管理表**:
- `registered_models` - 注册模型
- `model_versions` - 模型版本
- `logged_models` - 记录的模型
- `logged_model_params` - 模型参数
- `logged_model_metrics` - 模型指标
- `logged_model_tags` - 模型标签

**标签和元数据表**:
- `experiment_tags` - 实验标签
- `tags` - 运行标签
- `input_tags` - 输入标签
- `registered_model_tags` - 模型标签
- `model_version_tags` - 版本标签
- `registered_model_aliases` - 模型别名

**追踪和系统表**:
- `trace_info` - 追踪信息
- `trace_request_metadata` - 追踪请求元数据
- `trace_tags` - 追踪标签
- `latest_metrics` - 最新指标
- `alembic_version` - 数据库版本

## 💡 数据洞察

### 实验表现
- ✅ **成功运行**: 1个完整运行，状态为FINISHED
- 📊 **训练效果**: 准确率提升19.5% (70.39% → 89.89%)
- ⏱️ **执行效率**: 4.7秒完成5个epoch训练
- 💾 **数据规模**: 100样本，3特征的二分类任务

### 存储效率
- 🗄️ **元数据**: 264K SQLite数据库
- 📁 **Artifacts**: 56K 模型和文件存储
- 🔄 **版本控制**: 完整的模型版本管理
- 🏷️ **标签系统**: 丰富的元数据标签支持

---

**生成时间**: 2025-07-29  
**数据库版本**: MLflow 3.1.4  
**记录总数**: 21条核心记录 