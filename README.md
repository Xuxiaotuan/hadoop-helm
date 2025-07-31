# Hadoop Helm Chart

这是一个用于在Kubernetes上部署Hadoop HDFS高可用集群的Helm chart。本chart基于Hadoop 3.3.6构建，提供了完整的HDFS分布式文件系统功能，包括NameNode高可用、JournalNode集群和数据节点存储。

## 核心能力

- **NameNode高可用(HA)**：支持2个NameNode实例，通过JournalNode实现元数据同步
- **持久化存储**：所有组件使用本地存储卷，确保数据持久性
- **自动配置**：自动生成HDFS配置文件(core-site.xml, hdfs-site.xml)
- **一键部署**：提供部署脚本简化集群生命周期管理
- **资源清理**：支持彻底清理所有资源，包括PV和节点存储目录
- **健康检查**：所有Pod包含就绪探针和存活探针
- **资源管理**：支持为各组件配置资源限制

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

## 部署流程详解

### 1. 使用部署脚本（推荐方法）

部署脚本 `deploy.sh` 提供完整的集群生命周期管理功能。脚本执行以下操作：

#### 步骤1: 授予执行权限
```bash
chmod +x deploy.sh
```

#### 步骤2: 部署集群到hadoop命名空间
```bash
./deploy.sh deploy -n hadoop
```

**执行过程**:
1. 创建命名空间（如果不存在）
2. 检查并创建本地PV（使用local-storage存储类）
3. 在节点上创建存储目录：
   - `/mnt/hadoop/namenode`
   - `/mnt/hadoop/datanode`
   - `/mnt/hadoop/journalnode`
4. 使用Helm安装Hadoop集群
5. 等待所有Pod就绪（最长等待10分钟）

**预期结果**:
- 输出: "Hadoop cluster deployed successfully in namespace hadoop"
- 3个NameNode Pod（1个active，2个standby）
- 3个DataNode Pod
- 3个JournalNode Pod
- 所有Pod状态为Running

#### 步骤3: 验证集群状态
```bash
./deploy.sh status -n hadoop
```

**执行过程**:
1. 检查命名空间是否存在
2. 列出所有相关Pod的状态
3. 显示PVC/PV绑定状态
4. 显示存储使用情况

**预期结果**:
```
NAMESPACE: hadoop
PODS:
NAME                            READY   STATUS    RESTARTS   AGE
hadoop-datanode-0              1/1     Running   0          2m
hadoop-datanode-1              1/1     Running   0          2m
hadoop-datanode-2              1/1     Running   0          2m
hadoop-journalnode-0           1/1     Running   0          2m
hadoop-journalnode-1           1/1     Running   0          2m
hadoop-journalnode-2           1/1     Running   0          2m
hadoop-namenode-0              1/1     Running   0          2m
hadoop-namenode-1              1/1     Running   0          2m

STORAGE:
NAME                                     STATUS   VOLUME                                     CAPACITY   ACCESS MODES
persistentvolumeclaim/datanode-hadoop   Bound    pvc-df4e3f2e-...                           20Gi       RWO
...
```

#### 步骤4: 访问HDFS集群
```bash
# 获取active NameNode的Pod名称
ACTIVE_NN=$(kubectl get pod -n hadoop -l app.kubernetes.io/component=namenode -o jsonpath='{.items[?(@.metadata.annotations.hdfs\.namenode\.ha\.state=="active")].metadata.name}')

# 进入容器执行HDFS命令
kubectl exec -it -n hadoop $ACTIVE_NN -- bash

# 在容器内创建测试目录
hdfs dfs -mkdir /test

# 在容器内上传文件
hdfs dfs -put /etc/hosts /test/hosts

# 在容器内查看文件
hdfs dfs -ls /test
```

**预期结果**:
```
Found 1 items
-rw-r--r--   3 root supergroup        221 2023-07-31 08:15 /test/hosts
```

#### 步骤5: 故障转移测试
```bash
# 手动触发故障转移
kubectl exec -it -n hadoop hadoop-namenode-0 -- hdfs haadmin -failover active standby

# 验证新的active NameNode
kubectl get pod -n hadoop -l app.kubernetes.io/component=namenode -o jsonpath='{.items[*].metadata.annotations.hdfs\.namenode\.ha\.state}'
```

**预期结果**:
```
"standby" "active" # 显示新的active节点
```

#### 步骤6: 扩容DataNode
1. 编辑 `values.yaml`:
```yaml
hdfs:
  dataNode:
    replicas: 5  # 从3增加到5
```
2. 执行升级:
```bash
./deploy.sh upgrade -n hadoop
```

**预期结果**:
- 新增2个DataNode Pod
- 集群自动识别新节点
- HDFS容量增加

#### 步骤7: 卸载集群
```bash
# 普通卸载（保留数据）
./deploy.sh uninstall -n hadoop

# 强制卸载（清除所有数据）
./deploy.sh uninstall -n hadoop --force
```

**执行过程**:
1. Helm卸载应用
2. 删除PVC（普通卸载保留）
3. 删除PV（普通卸载保留）
4. 清理节点存储目录（仅--force时）
5. 删除命名空间（仅--force时）

### 2. 直接使用Helm命令（高级用户）

适合需要更多控制权的用户：

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

## 配置参考

### 架构概述

```
+-----------------------------------------------------------------------+
|                            Hadoop HDFS Cluster                        |
+-------------------+-------------------+-------------------+-----------+
|   NameNode (Active) |   NameNode (Standby) |   JournalNode Quorum    |
|       (NN0)       |       (NN1)       |  (JN0, JN1, JN2)  |           |
+-------------------+-------------------+-------------------+           |
        |                   |                   |                      |
        |                   |                   |                      |
        |                   |                   |                      |
+-------------------+-------------------+-------------------+           |
|   DataNode        |   DataNode        |   DataNode        |           |
|     (DN0)         |     (DN1)         |     (DN2)         |           |
+-------------------+-------------------+-------------------+-----------+
```

### 配置选项

所有参数均可在 `values.yaml` 中调整。修改后需要执行 `./deploy.sh upgrade -n hadoop` 使配置生效。

#### 主要配置参数

| 参数 | 描述 | 默认值 | 配置建议 |
|------|------|--------|----------|
| **全局配置** ||||
| logLevel | 日志级别 | INFO | 生产环境建议WARN |
| antiAffinity | Pod反亲和性策略 | "soft" | 生产环境建议"hard" |
| **HDFS配置** ||||
| hdfs.clusterName | HDFS集群名称 | "min-hadoop" | 根据实际环境命名 |
| hdfs.rpcAddress | HDFS RPC地址 | "min-hadoop" | 保持默认 |
| hdfs.nameNode.replicas | NameNode副本数 | 2 | 固定为2（active+standby） |
| hdfs.dataNode.replicas | DataNode副本数 | 3 | 根据数据量和性能需求调整 |
| hdfs.journalNode.replicas | JournalNode副本数 | 3 | 必须为奇数（3/5/7） |
| hdfs.replication | 数据复制因子 | 3 | 根据数据重要性调整（2-5） |
| hdfs.webhdfs.enabled | WebHDFS服务开关 | false | 需要REST API时启用 |
| **持久化存储配置** ||||
| persistence.nameNode.enabled | NameNode持久化开关 | true | 生产环境必须启用 |
| persistence.nameNode.size | NameNode存储大小 | "10Gi" | 根据元数据量调整 |
| persistence.nameNode.storageClass | 存储类名称 | "local-storage" | 可用SSD提升性能 |
| persistence.dataNode.enabled | DataNode持久化开关 | true | 生产环境必须启用 |
| persistence.dataNode.size | DataNode存储大小 | "20Gi" | 根据数据量调整 |
| persistence.dataNode.accessMode | 存储访问模式 | "ReadWriteOnce" | 保持默认 |
| persistence.dataNode.storageClass | 存储类名称 | "local-storage" | 高IO需求建议SSD |
| persistence.journalNode.enabled | JournalNode持久化开关 | true | 生产环境必须启用 |
| persistence.journalNode.size | JournalNode存储大小 | "5Gi" | 保持默认 |
| persistence.journalNode.accessMode | 存储访问模式 | "ReadWriteOnce" | 保持默认 |
| persistence.journalNode.storageClass | 存储类名称 | "local-storage" | 建议与NameNode相同 |
| **镜像配置** ||||
| image.repository | Docker镜像仓库 | hadoop-xxt | 可替换为私有仓库 |
| image.tag | 镜像标签 | "3.3.6" | 升级前需充分测试 |
| image.pullPolicy | 镜像拉取策略 | IfNotPresent | 生产环境建议Always |

#### 高级配置示例

```yaml
# 生产环境配置示例
logLevel: "WARN"
antiAffinity: "hard"

hdfs:
  clusterName: "prod-hadoop"
  dataNode:
    replicas: 10  # 10个数据节点
    resources:
      limits:
        memory: "4Gi"
        cpu: "2"
  replication: 3

persistence:
  dataNode:
    size: "1Ti"  # 每个DataNode 1TB存储
    storageClass: "ssd"  # 使用SSD存储类

image:
  repository: "registry.example.com/hadoop"
  pullPolicy: "Always"
```

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

## 支持矩阵

| 功能                     | 支持状态 | 说明                                                                 |
|--------------------------|----------|----------------------------------------------------------------------|
| NameNode HA              | ✅ 完全支持 | 基于JournalNode的自动故障转移                                       |
| 持久化存储               | ✅ 完全支持 | 使用本地存储卷                                                      |
| HDFS Federation          | ❌ 不支持  | 单命名空间部署                                                     |
| YARN/MR集成              | ❌ 不支持  | 仅HDFS功能                                                         |
| Kerberos认证             | ❌ 不支持  | 未配置安全认证                                                     |
| 动态节点扩缩容           | ✅ 部分支持 | DataNode支持扩容，NameNode需手动调整                               |
| 跨可用区部署             | ❌ 不支持  | 所有节点部署在同一区域                                             |
| 监控集成                 | ⚠️ 部分支持 | 暴露JMX指标，需自行配置监控系统                                    |
| 多版本Hadoop支持         | ⚠️ 部分支持 | 仅测试3.3.6版本                                                    |

## 故障排除指南

### 常见问题解决方案

1. **Pod无法启动**
   - 检查点：
     - 节点资源是否充足（`kubectl describe node`）
     - 存储类是否可用（`kubectl get storageclass`）
     - 节点是否有存储目录权限
   - 解决方案：
     - 扩容节点资源
     - 创建所需StorageClass
     - 手动创建存储目录并设置权限

2. **HDFS无法访问**
   - 检查点：
     - NameNode服务状态（`kubectl logs <namenode-pod>`）
     - JournalNode是否全部就绪
     - 网络策略是否允许通信
   - 解决方案：
     - 检查NameNode日志中的异常
     - 确保至少2个JournalNode运行
     - 检查网络策略配置

3. **数据持久性问题**
   - 检查点：
     - PVC绑定状态（`kubectl get pvc -n hadoop`）
     - PV创建情况（`kubectl get pv`）
     - 节点存储空间
   - 解决方案：
     - 检查存储类配置
     - 清理或扩容节点存储
     - 验证本地卷配置

4. **高可用切换失败**
   - 检查点：
     - JournalNode日志是否正常
     - NameNode之间的网络连通性
     - ZKFC进程状态
   - 解决方案：
     - 检查JournalNode Pod日志
     - 验证网络策略
     - 手动执行故障转移命令

### 诊断命令参考

```bash
# 检查HDFS状态
kubectl exec -n hadoop <active-namenode> -- hdfs dfsadmin -report

# 检查HA状态
kubectl exec -n hadoop <active-namenode> -- hdfs haadmin -getServiceState nn0
kubectl exec -n hadoop <active-namenode> -- hdfs haadmin -getServiceState nn1

# 检查JournalNode状态
kubectl exec -n hadoop <journalnode-pod> -- hdfs dfs -ls journalnode://hadoop-journalnode:8485

# 获取详细日志
kubectl logs -n hadoop <pod-name> --tail 1000 | grep -i error
```

### 获取帮助

查看脚本内置帮助：

```bash
./deploy.sh help
```

检查组件日志：
```bash
# NameNode日志
kubectl logs -l app.kubernetes.io/component=namenode -n hadoop

# DataNode日志
kubectl logs -l app.kubernetes.io/component=datanode -n hadoop

# JournalNode日志
kubectl logs -l app.kubernetes.io/component=journalnode -n hadoop
```

## 贡献与支持

如需报告问题或贡献代码，请访问项目仓库：
https://github.com/your-repo/hadoop-helm

对于企业级支持需求，请联系：support@example.com
