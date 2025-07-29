#!/usr/bin/env python3
import mlflow
import pandas as pd
import numpy as np
import time
import os

def test_local_mlflow():
    print("🔍 开始测试本地MLflow服务器...")
    
    # 设置MLflow tracking URI为本地服务器
    mlflow.set_tracking_uri("http://127.0.0.1:3111")
    
    try:
        # 测试连接
        print(f"📍 MLflow Tracking URI: {mlflow.get_tracking_uri()}")
        
        # 创建实验
        experiment_name = f"本地测试实验_{int(time.time())}"
        try:
            experiment_id = mlflow.create_experiment(experiment_name)
            print(f"✅ 创建实验成功: {experiment_name} (ID: {experiment_id})")
        except Exception as e:
            print(f"⚠️  实验创建失败，可能已存在: {e}")
            experiment_id = mlflow.get_experiment_by_name(experiment_name)
            if experiment_id:
                experiment_id = experiment_id.experiment_id
            else:
                experiment_id = "0"  # 使用默认实验
        
        # 开始运行
        with mlflow.start_run(experiment_id=experiment_id, run_name="本地测试运行"):
            print("🚀 开始测试运行...")
            
            # 记录参数
            params = {
                "learning_rate": 0.01,
                "batch_size": 32,
                "epochs": 10,
                "model_type": "local_test"
            }
            for key, value in params.items():
                mlflow.log_param(key, value)
            print("📝 参数记录成功")
            
            # 记录指标（模拟训练过程）
            for epoch in range(5):
                accuracy = 0.7 + epoch * 0.05 + np.random.normal(0, 0.02)
                loss = 1.0 - epoch * 0.15 + np.random.normal(0, 0.05)
                mlflow.log_metric("accuracy", accuracy, step=epoch)
                mlflow.log_metric("loss", loss, step=epoch)
            print("📊 指标记录成功")
            
            # 记录数据集
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
            print("💾 数据集记录成功")
            
            # 创建并记录artifact
            artifact_content = f"""
本地MLflow测试报告
==================
测试时间: {time.strftime('%Y-%m-%d %H:%M:%S')}
实验名称: {experiment_name}
服务器地址: http://127.0.0.1:3111

测试结果：
- 连接状态: ✅ 成功
- 参数记录: ✅ 成功
- 指标记录: ✅ 成功
- 数据集记录: ✅ 成功
- 上传: ✅ 成功

MLflow本地部署测试完成！
            """
            
            with open("test_report.txt", "w", encoding="utf-8") as f:
                f.write(artifact_content)
            
            mlflow.log_artifact("test_report.txt", "reports")
            print("📄 文件上传成功")
            
            # 记录模型（简单示例）
            from sklearn.linear_model import LogisticRegression
            from sklearn.datasets import make_classification
            
            X, y = make_classification(n_samples=100, n_features=4, random_state=42)
            model = LogisticRegression()
            model.fit(X, y)
            
            mlflow.sklearn.log_model(model, "model", registered_model_name="本地测试模型")
            print("🤖 模型记录成功")
            
            # 获取运行信息
            run = mlflow.active_run()
            print(f"🏃 运行ID: {run.info.run_id}")
            print(f"🧪 实验ID: {run.info.experiment_id}")
        
        print("\n" + "="*50)
        print("🎉 MLflow本地服务器测试完全成功！")
        print("\n📊 服务访问信息:")
        print(f"- MLflow UI: http://127.0.0.1:3111")
        print(f"- 数据库: SQLite (my.db)")
        print("="*50)
        
        return True
        
    except Exception as e:
        print(f"❌ 测试失败: {str(e)}")
        import traceback
        traceback.print_exc()
        return False
    finally:
        # 清理临时文件
        for temp_file in ["test_report.txt"]:
            if os.path.exists(temp_file):
                os.remove(temp_file)
                print(f"🧹 清理临时文件: {temp_file}")

if __name__ == "__main__":
    print("🧪 MLflow本地服务器测试脚本")
    print("=" * 50)
    success = test_local_mlflow()
    if success:
        print("\n✅ 所有测试通过！可以访问 http://127.0.0.1:3111 查看MLflow界面")
    else:
        print("\n❌ 测试失败，请检查MLflow服务器状态") 