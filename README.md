# Hadoop HDFS 集群（Kubernetes 部署方案）

## 项目概述

本项目提供一套基于 Kubernetes（K8s）的 Hadoop HDFS 集群完整部署方案，通过 Helm Chart 实现自动化编排与管理。方案聚焦高可用性、数据可靠性和运维便捷性，支持
NameNode 自动故障转移、数据持久化存储及外部便捷访问，适用于生产环境的分布式数据存储场景。

## 核心优势

- **高可用架构**：采用双副本 NameNode（Active/Standby 模式）+ 3 副本 JournalNode 实现元数据高可用，结合 ZooKeeper 完成自动故障转移
- **数据安全保障**：通过 PersistentVolumeClaim（PVC）持久化存储 NameNode 元数据、DataNode 数据和 JournalNode 日志
- **智能调度策略**：利用 K8s 反亲和性配置，确保核心组件分散在不同节点
- **自动化运维**：内置启动脚本实现组件初始化、状态监控及标签动态更新
- **灵活访问控制**：提供 Ingress 配置，支持外部通过自定义域名访问 NameNode WebUI

## 组件架构

| 组件           | 功能描述                                                                 | 部署方式               | 关键参数（`values.yaml`）                  |
|----------------|------------------------------------------------------------------------|-----------------------|------------------------------------------|
| NameNode（NN） | 管理文件系统元数据，协调集群操作                                         | StatefulSet（2 副本）  | `hdfs.nameNode.replicas=2`              |
| JournalNode（JN） | 同步 NameNode 编辑日志，确保元数据一致性                                 | StatefulSet（≥3 副本） | `hdfs.journalNode.replicas=3`           |
| DataNode（DN） | 存储实际数据块，处理客户端读写请求                                       | StatefulSet（≥3 副本） | `hdfs.dataNode.replicas=3`              |
| ZKFC           | 依赖 ZooKeeper 监控 NameNode 状态，触发自动故障转移                      | 嵌入 NN 容器           | `hdfs.nameNode.zookeeperQuorum`         |
| Ingress        | 外部访问 NameNode WebUI 的入口                                          | Ingress 资源           | `spec.rules[0].host=ssc-hn.hdfs.webui.com` |

## 部署环境要求

### 基础环境

- **Kubernetes 集群**：v1.21 及以上版本，节点数量 ≥ 3
- **Helm 客户端**：v3.0 及以上
- **ZooKeeper 集群**：3 节点及以上，提供节点访问地址
- **存储类（StorageClass）**：支持 `ReadWriteOnce` 访问模式

### 网络与权限

- **内部网络**：集群内 Pod 间需网络互通
- **外部访问**：配置 DNS 解析（将域名映射到 K8s 集群入口 IP）
- **权限要求**：部署用户需具备 `cluster-admin` 权限

## 快速部署指南

### 步骤 1：准备配置文件

创建 `values.yaml` 文件：

```yaml
image:
  repository: your-registry/hadoop
  tag: 3.3.4

hdfs:
  clusterName: my-hdfs-cluster
  nameNode:
    zookeeperQuorum: "zk-0:2181,zk-1:2181,zk-2:2181"
    resources:
      requests:
        cpu: 1000m
        memory: 2Gi
  dataNode:
    replicas: 3
  journalNode:
    replicas: 3

persistence:
  nameNode:
    enabled: true
    storageClass: "hdfs-nn-storage"
    size: 10Gi
  dataNode:
    enabled: true
    storageClass: "hdfs-dn-storage"
    size: 100Gi
```

### 步骤 2：部署集群

```bash
# 创建命名空间
kubectl create namespace hdfs

# Helm 部署
helm install hdfs-cluster ./hadoop -f values.yaml -n hdfs

# 验证部署状态
kubectl get pods -n hdfs -o wide
kubectl get statefulset -n hdfs
```

## 集群访问与验证

### 访问 NameNode WebUI

1. 配置 DNS 解析：`ssc-hn.hdfs.webui.com` → K8s 入口 IP
2. 浏览器访问：`http://ssc-hn.hdfs.webui.com`

### 执行 HDFS 命令

```bash
kubectl exec -it -n hdfs hdfs-cluster-hdfs-nn-0 -- bash

# 查看集群报告
hdfs dfsadmin -report

# 创建测试目录
hdfs dfs -mkdir /test
```

## 日常运维操作

### 组件管理

```bash
# 重启 NameNode
kubectl rollout restart statefulset/hdfs-cluster-hdfs-nn -n hdfs

# 扩容 DataNode
helm upgrade hdfs-cluster ./hadoop -f values.yaml -n hdfs --set hdfs.dataNode.replicas=5
```

### 故障转移测试

```bash
# 删除当前 Active NameNode Pod
kubectl delete pod -n hdfs <active-nn-pod-name>

# 验证切换结果
kubectl get pods -n hdfs -l hdfs.nn.state=active
```

## 卸载集群

```bash
# 卸载 Helm 发布（保留数据）
helm uninstall hdfs-cluster -n hdfs

# 彻底清理（删除所有数据）
kubectl delete pvc -n hdfs --all
kubectl delete namespace hdfs
```

## 注意事项

1. **数据持久化**：
    - 生产环境必须启用 `persistence.enabled=true`
    - 存储类需支持 `ReadWriteOnce` 访问模式

2. **资源配置**：
    - NameNode 建议配置 2Gi+ 内存
    - DataNode 资源配置需根据数据量和负载调整

3. **安全建议**：
    - 启用 HDFS 权限控制
    - 定期备份 NameNode 元数据

## 版本历史

| 版本   | 日期         | 变更说明                 |
|------|------------|----------------------|
| v1.0 | 2025-07-01 | 初始版本，支持 Hadoop 3.3.6 |

## 联系方式

- **维护团队**：大数据平台组
- **联系邮箱**：bjwanyi@foxmail.com
- **微信**：18618325651
- **问题反馈**：[提交 Issue](https://github.com/sfwanyi/hadoop-helm.git)
