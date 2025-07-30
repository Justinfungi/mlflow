#!/usr/bin/env python3
"""
MLflow 备份恢复 API 服务
提供 REST API 接口用于管理 MLflow 备份和恢复操作
"""

import os
import json
import subprocess
import logging
from datetime import datetime, timedelta
from pathlib import Path
from typing import List, Dict, Any, Optional
import asyncio

from fastapi import FastAPI, HTTPException, BackgroundTasks, Query, Path as FastAPIPath
from fastapi.responses import JSONResponse, FileResponse
from pydantic import BaseModel, Field
from uvicorn import run

# 配置
BACKUP_BASE_DIR = os.getenv("BACKUP_DIR", "/backup/mlflow")
BACKUP_SCRIPT = "/app/backup_services/backup_mlflow.sh"
RESTORE_SCRIPT = "/app/backup_services/restore_mlflow_backup.sh"
API_PORT = int(os.getenv("BACKUP_API_PORT", "8080"))
API_HOST = os.getenv("BACKUP_API_HOST", "0.0.0.0")

# 日志配置
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# FastAPI 应用
app = FastAPI(
    title="MLflow Backup & Restore API",
    description="MLflow 备份和恢复管理 API",
    version="1.0.0"
)

# 数据模型
class BackupInfo(BaseModel):
    """备份信息模型"""
    name: str = Field(..., description="备份名称")
    path: str = Field(..., description="备份路径")
    size: str = Field(..., description="备份大小")
    created_at: datetime = Field(..., description="创建时间")
    type: str = Field(..., description="备份类型 (compressed/directory)")
    status: str = Field(default="completed", description="备份状态")

class RestoreRequest(BaseModel):
    """恢复请求模型"""
    backup_name: str = Field(..., description="要恢复的备份名称")
    mode: str = Field(default="full", description="恢复模式 (full/database/artifacts)")
    force: bool = Field(default=False, description="是否强制恢复")

class BackupRequest(BaseModel):
    """备份请求模型"""
    compress: bool = Field(default=True, description="是否压缩")
    email: Optional[str] = Field(None, description="通知邮箱")

class TaskStatus(BaseModel):
    """任务状态模型"""
    task_id: str = Field(..., description="任务ID")
    status: str = Field(..., description="任务状态 (running/completed/failed)")
    message: str = Field(default="", description="状态消息")
    created_at: datetime = Field(..., description="任务创建时间")
    completed_at: Optional[datetime] = Field(None, description="任务完成时间")
    result: Optional[Dict[str, Any]] = Field(None, description="任务结果")

# 全局状态管理
running_tasks: Dict[str, TaskStatus] = {}

# 工具函数
def run_command(command: List[str], timeout: int = 3600) -> Dict[str, Any]:
    """运行Shell命令"""
    try:
        logger.info(f"执行命令: {' '.join(command)}")
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False
        )
        
        return {
            "success": result.returncode == 0,
            "returncode": result.returncode,
            "stdout": result.stdout,
            "stderr": result.stderr
        }
    except subprocess.TimeoutExpired:
        return {
            "success": False,
            "returncode": -1,
            "stdout": "",
            "stderr": f"命令执行超时 ({timeout}秒)"
        }
    except Exception as e:
        return {
            "success": False,
            "returncode": -1,
            "stdout": "",
            "stderr": str(e)
        }

def parse_backup_name(filename: str) -> Optional[datetime]:
    """从备份文件名解析创建时间"""
    try:
        # mlflow_backup_20240101_120000.tar.gz -> 20240101_120000
        if filename.startswith("mlflow_backup_"):
            timestamp_str = filename[14:].replace(".tar.gz", "").replace(".tar", "")
            return datetime.strptime(timestamp_str, "%Y%m%d_%H%M%S")
    except ValueError:
        pass
    return None

def get_file_size(file_path: str) -> str:
    """获取文件大小的人类可读格式"""
    try:
        size_bytes = os.path.getsize(file_path)
        for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
            if size_bytes < 1024.0:
                return f"{size_bytes:.1f}{unit}"
            size_bytes /= 1024.0
        return f"{size_bytes:.1f}PB"
    except OSError:
        return "Unknown"

def get_dir_size(dir_path: str) -> str:
    """获取目录大小"""
    try:
        result = subprocess.run(
            ["du", "-sh", dir_path],
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout.split('\t')[0]
    except subprocess.CalledProcessError:
        return "Unknown"

async def run_backup_task(task_id: str, request: BackupRequest):
    """异步执行备份任务"""
    try:
        # 更新任务状态
        running_tasks[task_id].status = "running"
        running_tasks[task_id].message = "正在执行备份..."
        
        # 构建命令
        command = [BACKUP_SCRIPT]
        if request.compress:
            command.append("--compress")
        else:
            command.append("--no-compress")
        
        if request.email:
            command.extend(["--email", request.email])
        
        # 执行备份
        result = run_command(command, timeout=7200)  # 2小时超时
        
        if result["success"]:
            running_tasks[task_id].status = "completed"
            running_tasks[task_id].message = "备份成功完成"
            running_tasks[task_id].result = {
                "stdout": result["stdout"],
                "backup_dir": BACKUP_BASE_DIR
            }
        else:
            running_tasks[task_id].status = "failed"
            running_tasks[task_id].message = f"备份失败: {result['stderr']}"
            running_tasks[task_id].result = result
        
        running_tasks[task_id].completed_at = datetime.now()
        
    except Exception as e:
        running_tasks[task_id].status = "failed"
        running_tasks[task_id].message = f"备份异常: {str(e)}"
        running_tasks[task_id].completed_at = datetime.now()
        logger.error(f"备份任务异常: {e}")

async def run_restore_task(task_id: str, request: RestoreRequest):
    """异步执行恢复任务"""
    try:
        # 更新任务状态
        running_tasks[task_id].status = "running"
        running_tasks[task_id].message = "正在执行恢复..."
        
        # 构建命令
        command = [RESTORE_SCRIPT, f"--{request.mode}"]
        if request.force:
            command.append("--force")
        command.append(request.backup_name)
        
        # 执行恢复
        result = run_command(command, timeout=3600)  # 1小时超时
        
        if result["success"]:
            running_tasks[task_id].status = "completed"
            running_tasks[task_id].message = "恢复成功完成"
            running_tasks[task_id].result = {
                "stdout": result["stdout"],
                "mode": request.mode,
                "backup_used": request.backup_name
            }
        else:
            running_tasks[task_id].status = "failed"
            running_tasks[task_id].message = f"恢复失败: {result['stderr']}"
            running_tasks[task_id].result = result
        
        running_tasks[task_id].completed_at = datetime.now()
        
    except Exception as e:
        running_tasks[task_id].status = "failed"
        running_tasks[task_id].message = f"恢复异常: {str(e)}"
        running_tasks[task_id].completed_at = datetime.now()
        logger.error(f"恢复任务异常: {e}")

# API 端点

@app.get("/", summary="根路径", description="API 健康检查")
async def root():
    return {
        "service": "MLflow Backup & Restore API",
        "version": "1.0.0",
        "status": "running",
        "timestamp": datetime.now().isoformat(),
        "backup_dir": BACKUP_BASE_DIR
    }

@app.get("/health", summary="健康检查")
async def health_check():
    """健康检查端点"""
    try:
        # 检查备份目录
        backup_dir_exists = os.path.exists(BACKUP_BASE_DIR)
        
        # 检查脚本文件
        backup_script_exists = os.path.exists(BACKUP_SCRIPT)
        restore_script_exists = os.path.exists(RESTORE_SCRIPT)
        
        # 检查Docker
        docker_result = run_command(["docker", "ps"], timeout=10)
        docker_available = docker_result["success"]
        
        health_status = {
            "status": "healthy" if all([
                backup_dir_exists, 
                backup_script_exists, 
                restore_script_exists,
                docker_available
            ]) else "unhealthy",
            "checks": {
                "backup_directory": backup_dir_exists,
                "backup_script": backup_script_exists,
                "restore_script": restore_script_exists,
                "docker": docker_available
            },
            "timestamp": datetime.now().isoformat()
        }
        
        return health_status
        
    except Exception as e:
        return {
            "status": "unhealthy",
            "error": str(e),
            "timestamp": datetime.now().isoformat()
        }

@app.get("/backups", response_model=List[BackupInfo], summary="获取备份列表")
async def list_backups():
    """获取所有可用备份的列表"""
    try:
        backups = []
        backup_dir = Path(BACKUP_BASE_DIR)
        
        if not backup_dir.exists():
            return backups
        
        # 查找备份文件和目录
        for item in backup_dir.iterdir():
            if item.name.startswith("mlflow_backup_"):
                created_at = parse_backup_name(item.name)
                if not created_at:
                    continue
                
                if item.is_file():
                    size = get_file_size(str(item))
                    backup_type = "compressed"
                elif item.is_dir():
                    size = get_dir_size(str(item))
                    backup_type = "directory"
                else:
                    continue
                
                backup_info = BackupInfo(
                    name=item.name,
                    path=str(item),
                    size=size,
                    created_at=created_at,
                    type=backup_type
                )
                backups.append(backup_info)
        
        # 按时间排序（最新的在前）
        backups.sort(key=lambda x: x.created_at, reverse=True)
        return backups
        
    except Exception as e:
        logger.error(f"获取备份列表失败: {e}")
        raise HTTPException(status_code=500, detail=f"获取备份列表失败: {str(e)}")

@app.post("/backups", summary="创建新备份")
async def create_backup(request: BackupRequest, background_tasks: BackgroundTasks):
    """创建新的备份"""
    try:
        # 生成任务ID
        task_id = f"backup_{datetime.now().strftime('%Y%m%d_%H%M%S')}_{os.getpid()}"
        
        # 创建任务状态
        task_status = TaskStatus(
            task_id=task_id,
            status="pending",
            message="备份任务已创建，等待执行",
            created_at=datetime.now()
        )
        running_tasks[task_id] = task_status
        
        # 添加后台任务
        background_tasks.add_task(run_backup_task, task_id, request)
        
        return {
            "task_id": task_id,
            "message": "备份任务已启动",
            "status": "pending"
        }
        
    except Exception as e:
        logger.error(f"创建备份任务失败: {e}")
        raise HTTPException(status_code=500, detail=f"创建备份任务失败: {str(e)}")

@app.delete("/backups/{backup_name}", summary="删除备份")
async def delete_backup(backup_name: str = FastAPIPath(..., description="备份名称")):
    """删除指定的备份"""
    try:
        backup_path = Path(BACKUP_BASE_DIR) / backup_name
        
        if not backup_path.exists():
            raise HTTPException(status_code=404, detail="备份不存在")
        
        if backup_path.is_file():
            backup_path.unlink()
        elif backup_path.is_dir():
            import shutil
            shutil.rmtree(backup_path)
        
        return {"message": f"备份 {backup_name} 已删除"}
        
    except Exception as e:
        logger.error(f"删除备份失败: {e}")
        raise HTTPException(status_code=500, detail=f"删除备份失败: {str(e)}")

@app.get("/backups/{backup_name}/download", summary="下载备份")
async def download_backup(backup_name: str = FastAPIPath(..., description="备份名称")):
    """下载指定的备份文件"""
    try:
        backup_path = Path(BACKUP_BASE_DIR) / backup_name
        
        if not backup_path.exists():
            raise HTTPException(status_code=404, detail="备份不存在")
        
        if backup_path.is_file():
            return FileResponse(
                path=str(backup_path),
                filename=backup_name,
                media_type='application/octet-stream'
            )
        else:
            raise HTTPException(status_code=400, detail="只能下载压缩备份文件")
        
    except Exception as e:
        logger.error(f"下载备份失败: {e}")
        raise HTTPException(status_code=500, detail=f"下载备份失败: {str(e)}")

@app.post("/restore", summary="恢复备份")
async def restore_backup(request: RestoreRequest, background_tasks: BackgroundTasks):
    """从备份中恢复数据"""
    try:
        # 验证备份是否存在
        backup_path = Path(BACKUP_BASE_DIR) / request.backup_name
        if not backup_path.exists():
            raise HTTPException(status_code=404, detail="指定的备份不存在")
        
        # 生成任务ID
        task_id = f"restore_{datetime.now().strftime('%Y%m%d_%H%M%S')}_{os.getpid()}"
        
        # 创建任务状态
        task_status = TaskStatus(
            task_id=task_id,
            status="pending",
            message="恢复任务已创建，等待执行",
            created_at=datetime.now()
        )
        running_tasks[task_id] = task_status
        
        # 添加后台任务
        background_tasks.add_task(run_restore_task, task_id, request)
        
        return {
            "task_id": task_id,
            "message": "恢复任务已启动",
            "status": "pending",
            "backup_name": request.backup_name,
            "mode": request.mode
        }
        
    except Exception as e:
        logger.error(f"创建恢复任务失败: {e}")
        raise HTTPException(status_code=500, detail=f"创建恢复任务失败: {str(e)}")

@app.get("/tasks/{task_id}", response_model=TaskStatus, summary="获取任务状态")
async def get_task_status(task_id: str = FastAPIPath(..., description="任务ID")):
    """获取指定任务的状态"""
    if task_id not in running_tasks:
        raise HTTPException(status_code=404, detail="任务不存在")
    
    return running_tasks[task_id]

@app.get("/tasks", response_model=List[TaskStatus], summary="获取所有任务")
async def list_tasks(
    status: Optional[str] = Query(None, description="按状态过滤 (pending/running/completed/failed)"),
    limit: int = Query(50, description="返回数量限制")
):
    """获取任务列表"""
    tasks = list(running_tasks.values())
    
    if status:
        tasks = [task for task in tasks if task.status == status]
    
    # 按创建时间排序（最新的在前）
    tasks.sort(key=lambda x: x.created_at, reverse=True)
    
    return tasks[:limit]

@app.delete("/tasks/{task_id}", summary="删除任务记录")
async def delete_task(task_id: str = FastAPIPath(..., description="任务ID")):
    """删除指定任务的记录"""
    if task_id not in running_tasks:
        raise HTTPException(status_code=404, detail="任务不存在")
    
    task = running_tasks[task_id]
    if task.status == "running":
        raise HTTPException(status_code=400, detail="无法删除正在运行的任务")
    
    del running_tasks[task_id]
    return {"message": f"任务 {task_id} 已删除"}

@app.get("/stats", summary="获取统计信息")
async def get_stats():
    """获取备份统计信息"""
    try:
        backup_dir = Path(BACKUP_BASE_DIR)
        stats = {
            "backup_count": 0,
            "total_size": 0,
            "oldest_backup": None,
            "latest_backup": None,
            "disk_usage": {},
            "task_stats": {
                "total": len(running_tasks),
                "pending": 0,
                "running": 0,
                "completed": 0,
                "failed": 0
            }
        }
        
        if backup_dir.exists():
            backups = []
            total_size = 0
            
            for item in backup_dir.iterdir():
                if item.name.startswith("mlflow_backup_"):
                    created_at = parse_backup_name(item.name)
                    if created_at:
                        backups.append(created_at)
                    
                    if item.is_file():
                        total_size += item.stat().st_size
                    elif item.is_dir():
                        try:
                            result = subprocess.run(
                                ["du", "-sb", str(item)],
                                capture_output=True,
                                text=True,
                                check=True
                            )
                            dir_size = int(result.stdout.split()[0])
                            total_size += dir_size
                        except subprocess.CalledProcessError:
                            pass
            
            stats["backup_count"] = len(backups)
            stats["total_size"] = total_size
            
            if backups:
                backups.sort()
                stats["oldest_backup"] = backups[0].isoformat()
                stats["latest_backup"] = backups[-1].isoformat()
        
        # 磁盘使用情况
        try:
            result = subprocess.run(
                ["df", "-h", BACKUP_BASE_DIR],
                capture_output=True,
                text=True,
                check=True
            )
            lines = result.stdout.strip().split('\n')
            if len(lines) > 1:
                fields = lines[1].split()
                stats["disk_usage"] = {
                    "total": fields[1],
                    "used": fields[2],
                    "available": fields[3],
                    "use_percentage": fields[4]
                }
        except subprocess.CalledProcessError:
            pass
        
        # 任务统计
        for task in running_tasks.values():
            stats["task_stats"][task.status] += 1
        
        return stats
        
    except Exception as e:
        logger.error(f"获取统计信息失败: {e}")
        raise HTTPException(status_code=500, detail=f"获取统计信息失败: {str(e)}")

@app.post("/cleanup", summary="清理任务")
async def cleanup_tasks():
    """清理已完成的任务记录"""
    try:
        # 保留最近24小时内的任务
        cutoff_time = datetime.now() - timedelta(hours=24)
        
        tasks_to_remove = []
        for task_id, task in running_tasks.items():
            if task.status in ["completed", "failed"] and task.created_at < cutoff_time:
                tasks_to_remove.append(task_id)
        
        for task_id in tasks_to_remove:
            del running_tasks[task_id]
        
        return {
            "message": f"清理了 {len(tasks_to_remove)} 个任务记录",
            "removed_tasks": len(tasks_to_remove),
            "remaining_tasks": len(running_tasks)
        }
        
    except Exception as e:
        logger.error(f"清理任务失败: {e}")
        raise HTTPException(status_code=500, detail=f"清理任务失败: {str(e)}")

# 异常处理
@app.exception_handler(HTTPException)
async def http_exception_handler(request, exc):
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": exc.detail,
            "timestamp": datetime.now().isoformat()
        }
    )

@app.exception_handler(500)
async def internal_server_error_handler(request, exc):
    return JSONResponse(
        status_code=500,
        content={
            "error": "Internal Server Error",
            "timestamp": datetime.now().isoformat()
        }
    )

if __name__ == "__main__":
    logger.info(f"启动 MLflow 备份恢复 API 服务")
    logger.info(f"监听地址: {API_HOST}:{API_PORT}")
    logger.info(f"备份目录: {BACKUP_BASE_DIR}")
    logger.info(f"备份脚本: {BACKUP_SCRIPT}")
    logger.info(f"恢复脚本: {RESTORE_SCRIPT}")
    
    run(
        app,
        host=API_HOST,
        port=API_PORT,
        log_level="info"
    )