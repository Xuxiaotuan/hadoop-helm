# Hadoop Helm Chart

这是一个用于在Kubernetes上部署Hadoop HDFS的Helm chart，支持高可用（HA）模式。

## 特性

- **高可用NameNode**：支持多NameNode部署
- **持久化存储**：所有组件使用持久化存储
- **自动配置**：自动配置HDFS集群参数
- **一键部署**：提供部署脚本简化操作
- **资源清理**：支持彻底清理所有资源

## 配置说明

### 当前配置
- **NameNode**: 3个副本，使用持久化存储
- **DataNode**: 3个副本，使用持久化存储
- **JournalNode**: 3个副本，支持HDFS高可用
- **复制因子**: 3
- **存储**: 自动存储卷（使用默认StorageClass）

### 存储配置
- NameNode存储: 10Gi ReadWriteOnce
- DataNode存储: 20Gi ReadWriteOnce
- JournalNode存储: 5Gi ReadWriteOnce
- 使用默认StorageClass进行自动存储卷管理

## 先决条件

- Kubernetes 1.19+ 集群
- Helm 3+ 已安装
- 默认StorageClass已配置
- 节点满足资源要求

## 快速开始

### 1. 使用脚本一键部署/管理（推荐）

```bash
# 赋予脚本执行权限
chmod +x deploy.sh

# 部署到hadoop命名空间（自动创建本地PV）
./deploy.sh deploy -n hadoop

# 查看集群状态
./deploy.sh status -n hadoop

# 升级集群
./deploy.sh upgrade -n hadoop

# 卸载集群（普通卸载）
./deploy.sh uninstall -n hadoop

# 强制卸载（清理所有残留，包括PVC和本地PV）
./deploy.sh uninstall -n hadoop --force

# 清理命名空间内所有残留资源
./deploy.sh cleanup -n hadoop
```

### 2. 直接使用Helm命令

```bash
# 创建命名空间
kubectl create namespace hadoop

# 部署
helm install hadoop-cluster ./ --namespace hadoop --wait --timeout 10m

# 升级
helm upgrade hadoop-cluster ./ --namespace hadoop --wait --timeout 10m

# 卸载
helm uninstall hadoop-cluster -n hadoop
```

## 访问方式
- NameNode Web UI: `http://<pod-ip>:9870`
- DataNode Web UI: `http://<pod-ip>:9864`
- HDFS RPC: `hdfs://<namenode-pod>:9000`

## 注意事项
1. 确保集群有足够的存储资源
2. 确保有默认的StorageClass
3. 多NameNode高可用模式下，需启用JournalNode
4. DataNode会自动连接到可用的NameNode
5. 强制卸载/清理会删除所有数据，请谨慎操作
6. 脚本会自动检测local-storage存储类并创建本地PV
7. 部署时会自动在节点上创建存储目录
8. 卸载时会自动清理PV和存储目录
9. PV和存储目录使用命名空间前缀，避免与现有资源冲突

## 配置选项

所有参数均可在 `values.yaml` 中调整：

```yaml
# 基本配置
logLevel: INFO
antiAffinity: "soft"

# HDFS 配置
hdfs:
  clusterName: "min-hadoop"
  rpcAddress: "min-hadoop"
  nameNode:
    replicas: 2
  dataNode:
    replicas: 3
  journalNode:
    replicas: 3
  replication: 3
  webhdfs:
    enabled: false

# 持久化存储配置
persistence:
  nameNode:
    enabled: true
    size: "10Gi"
    accessMode: "ReadWriteOnce"
    storageClass: "local-storage"
  dataNode:
    enabled: true
    size: "20Gi"
    accessMode: "ReadWriteOnce"
    storageClass: "local-storage"
  journalNode:
    enabled: true
    size: "5Gi"
    accessMode: "ReadWriteOnce"
    storageClass: "local-storage"

# 镜像配置
image:
  repository: hadoop-xxt
  tag: "3.3.6"
  pullPolicy: IfNotPresent
```

## 故障排除

### 常见问题

1. **Pod无法启动**：检查存储类是否可用，节点是否有足够资源
2. **HDFS无法访问**：检查NameNode服务状态和日志
3. **存储问题**：确认PVC已正确创建和绑定
4. **高可用问题**：确保JournalNode正常运行

### 获取帮助

查看脚本内置帮助：

```bash
./deploy.sh help
```

检查组件日志：
```bash
kubectl logs -l app.kubernetes.io/component=namenode -n hadoop
kubectl logs -l app.kubernetes.io/component=datanode -n hadoop
kubectl logs -l app.kubernetes.io/component=journalnode -n hadoop
```
