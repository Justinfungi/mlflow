#!/bin/bash

# Docker容器资源监控脚本
# 监控MLflow相关容器的资源使用情况

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 容器名称
CONTAINERS=("mlflow-server" "mlflow-postgres")

# 显示模式：single(单次), continuous(持续), summary(摘要)
MODE=${1:-"single"}

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}    MLflow Docker 容器资源监控${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo "监控时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
}

get_container_stats() {
    local container=$1
    
    # 检查容器是否运行
    if ! docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        echo -e "${RED}❌ 容器 ${container} 未运行${NC}"
        return 1
    fi
    
    # 获取基本统计信息
    local stats=$(docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}\t{{.PIDs}}" $container)
    
    echo -e "${GREEN}📊 容器: ${container}${NC}"
    echo "$stats" | tail -n +2
    
    # 获取详细信息
    local info=$(docker inspect $container --format='{{.State.Status}}|{{.State.StartedAt}}|{{.RestartCount}}|{{.Config.Image}}')
    IFS='|' read -r status started restart_count image <<< "$info"
    
    echo "   状态: $status"
    echo "   启动时间: $(date -d $started '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo $started)"
    echo "   重启次数: $restart_count"
    echo "   镜像: $image"
    
    # 获取网络信息
    local ports=$(docker port $container 2>/dev/null)
    if [ ! -z "$ports" ]; then
        echo "   端口映射:"
        echo "$ports" | sed 's/^/     /'
    fi
    
    echo ""
}

get_system_overview() {
    echo -e "${YELLOW}🖥️  系统资源概览${NC}"
    echo "----------------------------------------"
    
    # Docker系统信息
    docker system df --format "table {{.Type}}\t{{.Total}}\t{{.Active}}\t{{.Size}}\t{{.Reclaimable}}"
    
    echo ""
    echo -e "${YELLOW}📈 主机资源使用情况${NC}"
    echo "----------------------------------------"
    
    # 内存使用情况
    if command -v free >/dev/null 2>&1; then
        echo "内存使用:"
        free -h | grep -E "(Mem|Swap)" | sed 's/^/  /'
    fi
    
    # 磁盘使用情况
    if command -v df >/dev/null 2>&1; then
        echo "磁盘使用:"
        df -h / | tail -n +2 | sed 's/^/  /'
    fi
    
    # CPU负载
    if [ -f /proc/loadavg ]; then
        echo "CPU负载: $(cat /proc/loadavg | cut -d' ' -f1-3)"
    fi
    
    echo ""
}

show_network_analysis() {
    echo -e "${BLUE}🌐 网络连接分析${NC}"
    echo "----------------------------------------"
    
    for container in "${CONTAINERS[@]}"; do
        if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
            echo "🔍 ${container} 网络连接:"
            
            # 获取容器IP
            local container_ip=$(docker inspect $container --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
            echo "   容器IP: $container_ip"
            
            # 检查端口连通性
            local ports=$(docker port $container 2>/dev/null | cut -d'-' -f1 | tr -d ' ')
            if [ ! -z "$ports" ]; then
                echo "   端口检查:"
                while IFS= read -r port; do
                    if [ ! -z "$port" ]; then
                        if nc -z localhost $(echo $port | cut -d':' -f2) 2>/dev/null; then
                            echo -e "     ${GREEN}✅ $port 可访问${NC}"
                        else
                            echo -e "     ${RED}❌ $port 不可访问${NC}"
                        fi
                    fi
                done <<< "$ports"
            fi
            echo ""
        fi
    done
}

continuous_monitor() {
    echo "🔄 启动持续监控模式 (按 Ctrl+C 退出)"
    echo "刷新间隔: 5秒"
    echo ""
    
    while true; do
        clear
        print_header
        
        for container in "${CONTAINERS[@]}"; do
            get_container_stats $container
        done
        
        get_system_overview
        
        echo "下次刷新: $(date -d '+5 seconds' '+%H:%M:%S')"
        sleep 5
    done
}

export_report() {
    local report_file="/home/feng.hao.jie/test/docker_resources_report_$(date +%Y%m%d_%H%M%S).txt"
    
    echo "📋 生成详细报告到: $report_file"
    
    {
        print_header
        
        for container in "${CONTAINERS[@]}"; do
            get_container_stats $container
        done
        
        get_system_overview
        show_network_analysis
        
        echo "========================================="
        echo "报告生成时间: $(date)"
        echo "========================================="
    } > "$report_file"
    
    echo -e "${GREEN}✅ 报告已保存到: $report_file${NC}"
}

# 主逻辑
case $MODE in
    "single"|"")
        print_header
        for container in "${CONTAINERS[@]}"; do
            get_container_stats $container
        done
        get_system_overview
        ;;
    "continuous"|"c")
        continuous_monitor
        ;;
    "summary"|"s")
        print_header
        echo -e "${GREEN}📋 容器状态摘要${NC}"
        docker ps --filter "name=mlflow" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.Image}}"
        echo ""
        docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" "${CONTAINERS[@]}"
        ;;
    "network"|"n")
        print_header
        show_network_analysis
        ;;
    "report"|"r")
        export_report
        ;;
    "help"|"h"|"-h"|"--help")
        echo "Docker容器监控脚本使用说明:"
        echo ""
        echo "用法: $0 [模式]"
        echo ""
        echo "模式选项:"
        echo "  single      单次查看 (默认)"
        echo "  continuous  持续监控模式"
        echo "  summary     简要摘要"
        echo "  network     网络连接分析"
        echo "  report      生成详细报告"
        echo "  help        显示此帮助信息"
        echo ""
        echo "示例:"
        echo "  $0              # 单次查看"
        echo "  $0 continuous   # 持续监控"
        echo "  $0 summary      # 简要摘要"
        echo "  $0 network      # 网络分析"
        echo "  $0 report       # 生成报告"
        ;;
    *)
        echo -e "${RED}❌ 未知模式: $MODE${NC}"
        echo "使用 '$0 help' 查看使用说明"
        exit 1
        ;;
esac 