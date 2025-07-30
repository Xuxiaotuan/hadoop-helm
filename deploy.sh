#!/bin/bash

# Hadoop Helm Chart 部署脚本
# 支持自动存储卷的3个namenode和3个datanode配置

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "$1 命令未找到，请先安装"
        exit 1
    fi
}

# 检查Kubernetes集群
check_k8s() {
    if ! kubectl cluster-info &> /dev/null; then
        log_error "无法连接到Kubernetes集群"
        exit 1
    fi
    log_info "Kubernetes集群连接正常"
}

# 检查Helm
check_helm() {
    check_command helm
    log_info "Helm版本: $(helm version --short)"
}

# 检查存储类
check_storage_class() {
    if ! kubectl get storageclass &> /dev/null; then
        log_warn "无法获取StorageClass信息"
        return
    fi
    
    default_sc=$(kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')
    if [ -n "$default_sc" ]; then
        log_info "默认StorageClass: $default_sc"
    else
        log_warn "未找到默认StorageClass，将使用空字符串"
    fi
}

# 部署Hadoop集群
deploy_hadoop() {
    local release_name=${1:-hadoop-cluster}
    local namespace=${2:-default}
    
    log_info "开始部署Hadoop集群..."
    log_info "Release名称: $release_name"
    log_info "命名空间: $namespace"
    
    # 创建命名空间（如果不存在）
    if [ "$namespace" != "default" ]; then
        kubectl create namespace $namespace --dry-run=client -o yaml | kubectl apply -f -
    fi
    
    # 部署Helm chart
    helm install $release_name ./ \
        --namespace $namespace \
        --wait \
        --timeout 10m
    
    if [ $? -eq 0 ]; then
        log_info "Hadoop集群部署成功！"
        log_info "查看Pod状态: kubectl get pods -n $namespace"
        log_info "查看服务: kubectl get svc -n $namespace"
        log_info "查看PVC: kubectl get pvc -n $namespace"
    else
        log_error "Hadoop集群部署失败"
        exit 1
    fi
}

# 升级Hadoop集群
upgrade_hadoop() {
    local release_name=${1:-hadoop-cluster}
    local namespace=${2:-default}
    
    log_info "开始升级Hadoop集群..."
    helm upgrade $release_name ./ \
        --namespace $namespace \
        --wait \
        --timeout 10m
    
    if [ $? -eq 0 ]; then
        log_info "Hadoop集群升级成功！"
    else
        log_error "Hadoop集群升级失败"
        exit 1
    fi
}

# 卸载Hadoop集群
uninstall_hadoop() {
    local release_name=${1:-hadoop-cluster}
    local namespace=${2:-default}
    local force_cleanup=${3:-false}
    
    log_warn "即将卸载Hadoop集群: $release_name"
    
    if [ "$force_cleanup" = "true" ]; then
        log_warn "将执行强制清理（包括PVC）"
        read -p "确认强制卸载吗？这将删除所有数据！(y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # 强制删除所有Pod
            log_info "强制删除Pod..."
            kubectl delete pods --all -n $namespace --force --grace-period=0 2>/dev/null || true
            
            # 强制删除StatefulSet
            log_info "强制删除StatefulSet..."
            kubectl delete statefulset --all -n $namespace --force --grace-period=0 2>/dev/null || true
            
            # 强制删除PVC
            log_info "强制删除PVC..."
            kubectl delete pvc --all -n $namespace --force --grace-period=0 2>/dev/null || true
            
            # 删除Helm release
            log_info "删除Helm release..."
            helm uninstall $release_name --namespace $namespace 2>/dev/null || true
            
            log_info "Hadoop集群已强制卸载"
        else
            log_info "取消强制卸载操作"
        fi
    else
        read -p "确认卸载吗？(y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # 先尝试正常卸载
            helm uninstall $release_name --namespace $namespace
            
            # 检查是否还有残留资源
            if kubectl get pods -n $namespace 2>/dev/null | grep -q .; then
                log_warn "检测到残留资源，建议使用 --force 选项进行强制清理"
            fi
            
            log_info "Hadoop集群已卸载"
        else
            log_info "取消卸载操作"
        fi
    fi
}

# 清理残留资源
cleanup_resources() {
    local namespace=${1:-default}
    
    log_warn "清理命名空间 $namespace 中的残留资源..."
    
    # 删除所有Pod
    kubectl delete pods --all -n $namespace --force --grace-period=0 2>/dev/null || true
    
    # 删除所有StatefulSet
    kubectl delete statefulset --all -n $namespace --force --grace-period=0 2>/dev/null || true
    
    # 删除所有PVC
    kubectl delete pvc --all -n $namespace --force --grace-period=0 2>/dev/null || true
    
    # 删除所有Service
    kubectl delete svc --all -n $namespace --force --grace-period=0 2>/dev/null || true
    
    # 删除所有ConfigMap
    kubectl delete configmap --all -n $namespace --force --grace-period=0 2>/dev/null || true
    
    # 删除所有Secret
    kubectl delete secret --all -n $namespace --force --grace-period=0 2>/dev/null || true
    
    log_info "残留资源清理完成"
}

# 显示帮助信息
show_help() {
    echo "Hadoop Helm Chart 部署脚本"
    echo ""
    echo "用法: $0 [命令] [选项]"
    echo ""
    echo "命令:"
    echo "  deploy   部署Hadoop集群"
    echo "  upgrade  升级Hadoop集群"
    echo "  uninstall 卸载Hadoop集群"
    echo "  cleanup  清理残留资源"
    echo "  status   查看集群状态"
    echo "  help     显示此帮助信息"
    echo ""
    echo "选项:"
    echo "  -r, --release NAME    Release名称 (默认: hadoop-cluster)"
    echo "  -n, --namespace NAME  命名空间 (默认: default)"
    echo "  --force              强制清理（用于卸载时）"
    echo ""
    echo "示例:"
    echo "  $0 deploy                    # 部署到默认命名空间"
    echo "  $0 deploy -n hadoop         # 部署到hadoop命名空间"
    echo "  $0 upgrade -r my-hadoop     # 升级名为my-hadoop的集群"
    echo "  $0 uninstall -n hadoop      # 卸载hadoop命名空间的集群"
    echo "  $0 uninstall -n hadoop --force  # 强制卸载（包括PVC）"
    echo "  $0 cleanup -n hadoop        # 清理残留资源"
}

# 查看集群状态
show_status() {
    local release_name=${1:-hadoop-cluster}
    local namespace=${2:-default}
    
    log_info "Hadoop集群状态:"
    echo ""
    
    echo "=== Pod状态 ==="
    kubectl get pods -n $namespace -l app.kubernetes.io/instance=$release_name
    
    echo ""
    echo "=== 服务状态 ==="
    kubectl get svc -n $namespace -l app.kubernetes.io/instance=$release_name
    
    echo ""
    echo "=== PVC状态 ==="
    kubectl get pvc -n $namespace -l app.kubernetes.io/instance=$release_name
    
    echo ""
    echo "=== StatefulSet状态 ==="
    kubectl get statefulset -n $namespace -l app.kubernetes.io/instance=$release_name
}

# 主函数
main() {
    local command=""
    local release_name="hadoop-cluster"
    local namespace="default"
    local force_cleanup="false"
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            deploy|upgrade|uninstall|cleanup|status|help)
                command=$1
                shift
                ;;
            -r|--release)
                release_name=$2
                shift 2
                ;;
            -n|--namespace)
                namespace=$2
                shift 2
                ;;
            --force)
                force_cleanup="true"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    if [ -z "$command" ]; then
        log_error "请指定命令"
        show_help
        exit 1
    fi
    
    # 执行命令
    case $command in
        deploy)
            check_k8s
            check_helm
            check_storage_class
            deploy_hadoop $release_name $namespace
            ;;
        upgrade)
            check_k8s
            check_helm
            upgrade_hadoop $release_name $namespace
            ;;
        uninstall)
            check_k8s
            check_helm
            uninstall_hadoop $release_name $namespace $force_cleanup
            ;;
        cleanup)
            check_k8s
            cleanup_resources $namespace
            ;;
        status)
            check_k8s
            show_status $release_name $namespace
            ;;
        help)
            show_help
            ;;
        *)
            log_error "未知命令: $command"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@" 