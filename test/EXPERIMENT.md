# 实验日志 (EXPERIMENT LOG)

## 版本 1.0.0 - MLflow本地部署测试环境搭建
**日期**: 2025-07-29  
**变更类型**: Configuration + Process + Results

### Assumptions (实验假设)
1. MLflow本地部署可以有效支持机器学习实验管理
2. SQLite作为后端存储足以满足单用户测试需求
3. 基于Python的测试脚本可以全面验证MLflow核心功能
4. 本地artifact存储能够正确保存模型和文件

### Configuration (环境配置)

#### 系统环境
- **操作系统**: Linux
- **Python环境**: conda base环境
- **MLflow版本**: 3.1.4
- **存储后端**: SQLite (my.db)
- **服务端口**: 3111

#### 测试配置
- **实验框架**: MLflow Tracking
- **数据库**: SQLite (`sqlite:///my.db`)
- **Artifact存储**: 本地文件系统 (`mlartifacts/`)
- **测试模型**: sklearn LogisticRegression
- **测试数据**: 100行模拟二分类数据集

### Process (实验过程)

#### 1. 环境搭建
1. 启动MLflow server服务器
   ```bash
   mlflow server --port 3111 --backend-store-uri sqlite:///my.db
   ```
2. 创建测试脚本 `test_mlflow_local.py`
3. 编写全面的功能测试用例

#### 2. 功能测试
- ✅ **实验创建**: 成功创建带时间戳的实验
- ✅ **参数记录**: 记录4个超参数 (learning_rate, batch_size, epochs, model_type)
- ✅ **指标跟踪**: 记录5个epoch的accuracy和loss指标
- ✅ **数据集记录**: 使用pandas DataFrame记录训练数据
- ✅ **文件上传**: 成功上传测试报告到reports目录
- ✅ **模型保存**: 保存sklearn模型及相关环境文件
- ✅ **Web界面**: 验证MLflow UI正常访问

#### 3. 存储验证
- 检查SQLite数据库完整性
- 验证artifact文件结构
- 确认模型文件序列化正确性

### Results (实验结果)

#### 成功指标
- **连接成功率**: 100%
- **功能测试通过率**: 100% (7/7项功能)
- **数据完整性**: ✅ 完整
- **Web界面可访问性**: ✅ 正常

#### 文件系统分析
```
总存储占用: ~332K
├── my.db (264K)           - 元数据存储完整
├── mlartifacts/ (56K)     - Artifact存储正常
├── mlruns/ (4.0K)         - 基本为空(符合预期)
└── test_mlflow_local.py (8.0K) - 测试脚本
```

#### Artifact存储结构验证
```
mlartifacts/1/
├── {run_id}/artifacts/reports/test_report.txt  - 文本文件 ✅
└── models/m-{model_id}/artifacts/              - 模型文件包 ✅
    ├── model.pkl          - 序列化模型
    ├── MLmodel           - 模型元数据
    ├── conda.yaml        - 环境配置
    ├── python_env.yaml   - Python环境
    └── requirements.txt  - 依赖列表
```

#### 性能表现
- **启动时间**: < 10秒
- **数据记录延迟**: < 1秒
- **模型保存时间**: < 5秒
- **Web界面响应**: < 2秒

### 结论与后续计划

#### 主要成果
1. **✅ 成功验证**: MLflow本地部署完全可行
2. **✅ 功能完整**: 所有核心功能正常工作
3. **✅ 存储稳定**: SQLite后端稳定可靠
4. **✅ 界面友好**: Web UI功能齐全

#### 发现的优势
- 部署简单，无需复杂配置
- 存储占用小，适合个人开发
- 功能全面，支持完整ML生命周期
- 界面直观，便于实验管理

#### 潜在改进点
1. 考虑添加用户认证
2. 评估PostgreSQL后端的必要性
3. 探索分布式artifact存储
4. 增加自动化测试覆盖率

#### 下一步计划
- [ ] 集成Docker化部署
- [ ] 添加模型版本管理测试
- [ ] 评估生产环境配置
- [ ] 编写更多ML框架集成示例

---

## 版本 1.1.0 - 数据库内容深度分析
**日期**: 2025-07-29  
**变更类型**: Process + Results

### Assumptions (分析假设)
1. SQLite数据库完整存储了所有MLflow元数据
2. 数据库结构反映了MLflow的核心架构设计
3. 查看数据库内容有助于理解MLflow的内部机制
4. 数据完整性验证可以确保实验记录的可靠性

### Configuration (分析配置)
- **数据库文件**: `/home/feng.hao.jie/test/my.db` (264K)
- **数据库类型**: SQLite 3
- **查询工具**: sqlite3 CLI
- **分析范围**: 全部21个数据表

### Process (分析过程)
1. **表结构探索**: 查看所有表名和创建语句
2. **核心数据检查**: 逐一查看experiments、runs、params、metrics等关键表
3. **关联关系分析**: 验证数据间的外键关联和逻辑一致性
4. **数据完整性验证**: 统计各表记录数，确认数据完整性

### Results (分析结果)

#### 数据库架构验证
- ✅ **表结构完整**: 21个表涵盖实验管理全生命周期
- ✅ **数据一致性**: 外键关联正确，无孤立记录
- ✅ **存储效率**: 264K存储1次完整实验的所有数据

#### 核心数据统计
| 数据类型 | 记录数 | 验证状态 |
|----------|--------|----------|
| 实验 | 2个 | ✅ 包含默认+自定义实验 |
| 运行 | 1个 | ✅ 状态FINISHED |
| 参数 | 4个 | ✅ 完整超参数集 |
| 指标 | 10个 | ✅ 5步accuracy+loss |
| 数据集 | 1个 | ✅ 100行×3列结构 |
| 模型 | 1个 | ✅ 版本1，状态READY |

#### 实验性能分析
- **训练效果**: 准确率从70.39%提升到89.89% (+19.5%)
- **收敛速度**: 5个epoch内达到89%准确率
- **损失下降**: 从1.018降至0.435 (-57%)
- **执行时间**: 4.7秒完成全流程

#### 存储结构洞察
```
数据存储分布:
├── 元数据 (my.db): 264K
│   ├── 实验定义和运行记录
│   ├── 参数和指标时间序列  
│   ├── 数据集元数据
│   └── 模型注册信息
└── 二进制文件 (mlartifacts): 56K
    ├── 序列化模型 (model.pkl)
    ├── 环境配置文件
    └── 测试报告文件
```

### 新发现与洞察

#### 架构优势
1. **关系型设计**: 清晰的表结构和外键约束
2. **版本控制**: 完整的模型版本管理机制
3. **可扩展性**: 支持标签、别名等扩展元数据
4. **追踪能力**: trace_info表支持分布式追踪

#### 存储优化
- 元数据与二进制文件分离存储
- SQLite适合单用户场景，轻量高效
- 支持增量指标记录，节省存储空间

---

## 版本 1.2.0 - 增强启动脚本支持PostgreSQL
**日期**: 2025-07-29  
**变更类型**: Configuration + Process

### Assumptions (新增假设)
1. PostgreSQL作为后端存储能提供更好的生产环境支持
2. 用户需要灵活选择SQLite或PostgreSQL的能力
3. 自动化脚本可以简化复杂的服务启动流程
4. Docker容器化PostgreSQL部署是最佳实践

### Configuration (新增配置)

#### 脚本架构
- **start_mlflow_local.sh**: 智能MLflow启动脚本
  - 支持SQLite和PostgreSQL双模式
  - 自动依赖检查和安装
  - 连接状态验证
- **start_postgres.sh**: PostgreSQL容器管理脚本
  - 容器状态检查和重用
  - 自动健康检查
  - 配置与docker-compose.yml一致

#### 数据库配置对比
| 参数 | SQLite | PostgreSQL |
|------|--------|------------|
| 连接URI | sqlite:///my.db | postgresql://mlflow_user:secure_password_123@localhost:3110/mlflow |
| 端口 | N/A | 3110 |
| 依赖 | 内置 | psycopg2-binary |
| 容器 | 无 | postgres:13 |

### Process (开发过程)

#### 1. 脚本增强设计
1. **参数化配置**: 使用环境变量支持自定义配置
2. **错误处理**: 添加连接测试和失败回退机制
3. **用户体验**: 提供清晰的状态反馈和使用指导
4. **兼容性**: 保持与原有SQLite模式的完全兼容

#### 2. 功能实现
- ✅ **多数据库支持**: SQLite + PostgreSQL
- ✅ **自动依赖管理**: psycopg2-binary自动安装
- ✅ **连接验证**: 启动前测试数据库连接
- ✅ **容器管理**: 智能Docker容器生命周期管理
- ✅ **配置统一**: 与docker-compose.yml保持一致

#### 3. 文档完善
- 创建完整的使用指南 (`MLflow_Usage_Guide.md`)
- 添加故障排除和最佳实践
- 提供场景对比和选择建议

### Results (增强结果)

#### 功能验证
- ✅ **SQLite模式**: 完全向后兼容，启动时间<3秒
- ✅ **PostgreSQL模式**: 支持生产级部署，启动时间<15秒
- ✅ **容器管理**: 自动检测和重用已有容器
- ✅ **错误处理**: 友好的错误提示和自动修复

#### 用户体验改进
```bash
# 简化的使用方式
./start_mlflow_local.sh          # SQLite模式
./start_postgres.sh              # 启动数据库
./start_mlflow_local.sh postgres # PostgreSQL模式
```

#### 配置灵活性
- 支持环境变量自定义所有数据库参数
- 与Docker Compose配置100%兼容
- 智能端口管理(3110数据库，3111服务器)

### 新增优势

#### 生产就绪性
1. **PostgreSQL支持**: 企业级数据库后端
2. **容器化部署**: 标准化的部署方式
3. **配置管理**: 环境变量驱动的配置系统
4. **健康检查**: 自动服务状态验证

#### 开发便利性
- 一键切换数据库后端
- 自动依赖管理和安装
- 详细的状态反馈和错误指导
- 完整的使用文档和故障排除

### 后续改进计划
- [ ] 添加Redis缓存支持
- [ ] 集成用户认证功能
- [ ] 支持集群模式部署
- [ ] 添加监控和日志收集

---

**实验执行者**: feng.hao.jie  
**环境**: Linux conda(factor)  
**状态**: ✅ 完成  
**置信度**: 高 