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

## 快速开始

### 1. 使用部署脚本（推荐）

```bash
# 授予脚本执行权限
chmod +x deploy.sh

# 部署集群到hadoop命名空间
./deploy.sh deploy -n hadoop

# 检查集群状态
./deploy.sh status -n hadoop
```

**执行过程**:
1. 创建命名空间（如果不存在）
2. 自动创建本地PV和存储目录
3. 安装Hadoop集群
4. 等待所有Pod就绪（约2-5分钟）

**预期结果**:
- 输出: "Hadoop cluster deployed successfully"
- 所有Pod状态为Running
- HDFS集群准备就绪

**验证部署成功**:
```bash
# 检查集群状态
./deploy.sh status -n hadoop

# 预期输出示例:
# === Pod状态 ===
# NAME                              READY   STATUS    RESTARTS   AGE
# hadoop-cluster-hadoop-hdfs-dn-0   1/1     Running   0          14m
# hadoop-cluster-hadoop-hdfs-dn-1   1/1     Running   0          5m35s
# hadoop-cluster-hadoop-hdfs-dn-2   1/1     Running   0          4m31s
# hadoop-cluster-hadoop-hdfs-jn-0   1/1     Running   0          14m
# hadoop-cluster-hadoop-hdfs-jn-1   1/1     Running   0          12m
# hadoop-cluster-hadoop-hdfs-jn-2   1/1     Running   0          10m
# hadoop-cluster-hadoop-hdfs-nn-0   1/1     Running   0          14m
# hadoop-cluster-hadoop-hdfs-nn-1   1/1     Running   0          7m5s

# === 服务状态 ===
# hadoop-cluster-hadoop-hdfs-nn-active   NodePort   10.233.27.125   <none>   9000:30900/TCP,9870:30987/TCP   14m
```

### 2. 访问集群

#### 验证集群状态
```bash
# 检查NameNode HA状态
kubectl exec -it hadoop-cluster-hadoop-hdfs-nn-0 -n hadoop -- hdfs haadmin -getServiceState nn0
# 输出: active

kubectl exec -it hadoop-cluster-hadoop-hdfs-nn-1 -n hadoop -- hdfs haadmin -getServiceState nn1  
# 输出: standby

# 检查DataNode注册状态
kubectl exec -it hadoop-cluster-hadoop-hdfs-nn-0 -n hadoop -- hdfs dfsadmin -report
```

**预期结果**:
- nn0为active状态，nn1为standby状态
- 所有DataNode正常注册（3个DataNode）
- 总容量约2.45TB，可用容量约1.99TB

#### 测试HDFS功能
```bash
# 进入NameNode容器
kubectl exec -it hadoop-cluster-hadoop-hdfs-nn-0 -n hadoop -- bash

# 创建测试目录
hdfs dfs -mkdir /test

# 创建测试文件
echo "Hello Hadoop" | hdfs dfs -put - /test/hello.txt

# 查看文件内容
hdfs dfs -cat /test/hello.txt
# 输出: Hello Hadoop

# 列出目录内容
hdfs dfs -ls /test
# 输出: Found 1 items -rw-r--r-- 3 hadoop supergroup 13 2025-07-31 15:43 /test/hello.txt
```

**预期结果**:
- 成功创建目录和文件
- 文件内容正确
- 权限和元数据正常

### 3. 管理集群

```bash
# 升级配置
./deploy.sh upgrade -n hadoop

# 卸载集群（保留数据）
./deploy.sh uninstall -n hadoop

# 完全清除（删除所有数据）
./deploy.sh uninstall -n hadoop --force
```

### 4. 直接使用Helm命令（高级用户）

```bash
# 创建命名空间
kubectl create ns hadoop

# 部署集群
helm install hadoop-cluster ./ -n hadoop

# 升级集群
helm upgrade hadoop-cluster ./ -n hadoop

# 卸载集群
helm uninstall hadoop-cluster -n hadoop
```

## 详细部署指南

对于更详细的部署说明、故障转移测试、扩容操作等，请参考下面的[详细部署步骤](#详细部署步骤)部分。



## 访问集群

### Web界面访问

#### 方法1：端口转发（推荐）
```bash
# NameNode Web界面
kubectl port-forward svc/hadoop-cluster-hadoop-hdfs-nn-active 9870:9870 -n hadoop
```
然后访问: `http://localhost:9870`

#### 方法2：NodePort访问
```bash
# 获取节点IP
kubectl get nodes -o wide

# 使用节点IP访问
http://<节点IP>:30987
```

#### 方法3：Java程序连接
```java
Configuration conf = new Configuration();
// 使用端口转发
conf.set("fs.defaultFS", "hdfs://localhost:9870");
// 或使用NodePort
conf.set("fs.defaultFS", "hdfs://<节点IP>:30900");
FileSystem fs = FileSystem.get(conf);
```

### 服务端口说明
- **NameNode Web UI**: `http://<pod-ip>:9870` (NodePort: 30987)
- **NameNode RPC**: `hdfs://<pod-ip>:9000` (NodePort: 30900)
- **DataNode Web UI**: `http://<pod-ip>:9864` (需要端口转发)
- **JournalNode Web UI**: `http://<pod-ip>:8480` (需要端口转发)

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

## 详细部署步骤

> 此部分提供更详细的部署和管理说明，适合需要深入了解操作细节的用户

### 1. 使用部署脚本

部署脚本 `deploy.sh` 提供完整的集群生命周期管理功能...

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

## 变更日志
- v1.1.0: 添加 JournalNode 支持，优化 HA 配置，移除无效 JN 格式化逻辑。
- v1.0.0: 初始版本，支持基本 HDFS 部署。

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

### 成功部署验证

当集群部署成功后，您应该看到：

1. **所有Pod运行正常**：
   - 3个DataNode Pod全部Running
   - 3个JournalNode Pod全部Running  
   - 2个NameNode Pod全部Running

2. **HA状态正确**：
   - nn0为active状态
   - nn1为standby状态

3. **DataNode注册成功**：
   - 3个DataNode全部注册到NameNode
   - 总容量约2.45TB，可用容量约1.99TB

4. **HDFS功能正常**：
   - 可以创建目录和文件
   - 文件读写操作正常
   - 权限和元数据正确

5. **Web界面可访问**：
   - 通过端口转发或NodePort可以访问NameNode Web界面
   - 可以看到集群状态、DataNode列表等信息

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
https://github.com/Xuxiaotuan/hadoop-helm

对于企业级支持需求，请联系：jia_yangchen@163.com
