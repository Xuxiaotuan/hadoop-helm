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
    
    # 检查是否使用local-storage，如果是则创建PV
    if kubectl get storageclass local-storage &>/dev/null; then
        log_info "检测到local-storage存储类，创建本地PV..."
        create_local_pvs $namespace
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
        log_warn "将执行强制清理（包括PVC和本地PV）"
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
            
            # 删除本地PV
            log_info "删除本地PV..."
            delete_local_pvs $namespace
            
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

# 清理Hadoop相关残留资源（只删带app=hadoop标签的）
cleanup_resources() {
    local namespace=${1:-default}
    
    log_warn "仅清理命名空间 $namespace 中 app=hadoop 的残留资源..."
    
    # 删除所有带app=hadoop标签的资源
    kubectl delete pods -l app=hadoop -n $namespace --force --grace-period=0 2>/dev/null || true
    kubectl delete statefulset -l app=hadoop -n $namespace --force --grace-period=0 2>/dev/null || true
    kubectl delete pvc -l app=hadoop -n $namespace --force --grace-period=0 2>/dev/null || true
    kubectl delete svc -l app=hadoop -n $namespace --force --grace-period=0 2>/dev/null || true
    kubectl delete configmap -l app=hadoop -n $namespace --force --grace-period=0 2>/dev/null || true
    kubectl delete secret -l app=hadoop -n $namespace --force --grace-period=0 2>/dev/null || true
    kubectl delete ingress -l app=hadoop -n $namespace --force --grace-period=0 2>/dev/null || true
    kubectl delete networkpolicy -l app=hadoop -n $namespace --force --grace-period=0 2>/dev/null || true
    kubectl delete rolebinding -l app=hadoop -n $namespace --force --grace-period=0 2>/dev/null || true
    kubectl delete role -l app=hadoop -n $namespace --force --grace-period=0 2>/dev/null || true
    kubectl delete serviceaccount -l app=hadoop -n $namespace --force --grace-period=0 2>/dev/null || true
    
    log_info "Hadoop相关残留资源清理完成"
}

# 创建本地PV
create_local_pvs() {
    local namespace=${1:-default}
    
    log_info "创建本地持久化卷..."
    
    # 获取节点列表
    local nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')
    local node_array=($nodes)
    local node_count=${#node_array[@]}
    
    if [ $node_count -lt 2 ]; then
        log_error "需要至少2个节点来部署Hadoop集群"
        exit 1
    fi
    
    log_info "检测到节点: ${node_array[*]}"
    
    # 创建PV配置文件，使用命名空间前缀避免冲突
    cat > /tmp/local-pvs-${namespace}.yaml << EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${namespace}-hadoop-nn-pv-0
  labels:
    namespace: ${namespace}
    app: hadoop
    type: namenode
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /mnt/data/${namespace}/hadoop-nn-0
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - ${node_array[0]}

---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${namespace}-hadoop-nn-pv-1
  labels:
    namespace: ${namespace}
    app: hadoop
    type: namenode
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /mnt/data/${namespace}/hadoop-nn-1
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - ${node_array[1]}

---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${namespace}-hadoop-nn-pv-2
  labels:
    namespace: ${namespace}
    app: hadoop
    type: namenode
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /mnt/data/${namespace}/hadoop-nn-2
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - ${node_array[0]}

---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${namespace}-hadoop-dn-pv-0
  labels:
    namespace: ${namespace}
    app: hadoop
    type: datanode
spec:
  capacity:
    storage: 20Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /mnt/data/${namespace}/hadoop-dn-0
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - ${node_array[0]}

---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${namespace}-hadoop-dn-pv-1
  labels:
    namespace: ${namespace}
    app: hadoop
    type: datanode
spec:
  capacity:
    storage: 20Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /mnt/data/${namespace}/hadoop-dn-1
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - ${node_array[1]}

---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${namespace}-hadoop-dn-pv-2
  labels:
    namespace: ${namespace}
    app: hadoop
    type: datanode
spec:
  capacity:
    storage: 20Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /mnt/data/${namespace}/hadoop-dn-2
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - ${node_array[0]}

---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${namespace}-hadoop-jn-pv-0
  labels:
    namespace: ${namespace}
    app: hadoop
    type: journalnode
spec:
  capacity:
    storage: 5Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /mnt/data/${namespace}/hadoop-jn-0
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - ${node_array[0]}

---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${namespace}-hadoop-jn-pv-1
  labels:
    namespace: ${namespace}
    app: hadoop
    type: journalnode
spec:
  capacity:
    storage: 5Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /mnt/data/${namespace}/hadoop-jn-1
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - ${node_array[1]}

---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${namespace}-hadoop-jn-pv-2
  labels:
    namespace: ${namespace}
    app: hadoop
    type: journalnode
spec:
  capacity:
    storage: 5Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /mnt/data/${namespace}/hadoop-jn-2
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - ${node_array[0]}
EOF

    # 在节点上创建目录
    log_info "在节点上创建存储目录..."
    for node in "${node_array[@]}"; do
        if [ "$node" = "${node_array[0]}" ]; then
            # 第一个节点
            ssh $node "sudo mkdir -p /mnt/data/${namespace}/hadoop-nn-0 /mnt/data/${namespace}/hadoop-nn-2 /mnt/data/${namespace}/hadoop-dn-0 /mnt/data/${namespace}/hadoop-dn-2 /mnt/data/${namespace}/hadoop-jn-0 /mnt/data/${namespace}/hadoop-jn-2 && sudo chmod 777 /mnt/data/${namespace}/hadoop-*" 2>/dev/null || log_warn "无法在节点 $node 上创建目录，请手动创建"
        else
            # 第二个节点
            ssh $node "sudo mkdir -p /mnt/data/${namespace}/hadoop-nn-1 /mnt/data/${namespace}/hadoop-dn-1 /mnt/data/${namespace}/hadoop-jn-1 && sudo chmod 777 /mnt/data/${namespace}/hadoop-*" 2>/dev/null || log_warn "无法在节点 $node 上创建目录，请手动创建"
        fi
    done
    
    # 应用PV配置
    kubectl apply -f /tmp/local-pvs-${namespace}.yaml
    
    # 验证PV创建
    if kubectl get pv | grep -q hadoop; then
        log_info "本地PV创建成功"
    else
        log_error "PV创建失败"
        exit 1
    fi
}

# 删除本地PV
delete_local_pvs() {
    local namespace=${1:-default}
    log_info "删除本地持久化卷..."
    
    # 删除指定命名空间的PV
    kubectl delete pv -l namespace=${namespace},app=hadoop 2>/dev/null || true
    
    # 获取节点列表
    local nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')
    local node_array=($nodes)
    
    # 清理节点上的目录
    log_info "清理节点上的存储目录..."
    for node in "${node_array[@]}"; do
        ssh $node "sudo rm -rf /mnt/data/${namespace}/hadoop-*" 2>/dev/null || log_warn "无法清理节点 $node 上的目录"
    done
    
    log_info "本地PV清理完成"
}

# 显示帮助信息
show_help() {
    echo "Hadoop Helm Chart 部署脚本"
    echo ""
    echo "用法: $0 [命令] [选项]"
    echo ""
    echo "命令:"
    echo "  deploy   部署Hadoop集群（自动创建本地PV）"
    echo "  upgrade  升级Hadoop集群"
    echo "  uninstall 卸载Hadoop集群"
    echo "  cleanup  清理残留资源"
    echo "  status   查看集群状态"
    echo "  help     显示此帮助信息"
    echo ""
    echo "选项:"
    echo "  -r, --release NAME    Release名称 (默认: hadoop-cluster)"
    echo "  -n, --namespace NAME  命名空间 (默认: default)"
    echo "  --force              强制清理（用于卸载时，包括本地PV）"
    echo ""
    echo "示例:"
    echo "  $0 deploy                    # 部署到默认命名空间"
    echo "  $0 deploy -n hadoop         # 部署到hadoop命名空间（自动创建PV）"
    echo "  $0 upgrade -r my-hadoop     # 升级名为my-hadoop的集群"
    echo "  $0 uninstall -n hadoop      # 卸载hadoop命名空间的集群"
    echo "  $0 uninstall -n hadoop --force  # 强制卸载（包括PVC和本地PV）"
    echo "  $0 cleanup -n hadoop        # 清理残留资源"
    echo ""
    echo "特性:"
    echo "  - 自动检测local-storage存储类"
    echo "  - 自动创建本地持久化卷"
    echo "  - 自动在节点上创建存储目录"
    echo "  - 卸载时自动清理PV和存储目录"
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