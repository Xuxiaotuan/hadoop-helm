# Hadoop Helm Chart

这是一个用于在Kubernetes上部署Hadoop HDFS的Helm chart。

## 配置说明

### 当前配置
- **NameNode**: 3个副本，使用持久化存储
- **DataNode**: 3个副本，使用持久化存储
- **复制因子**: 3
- **存储**: 自动存储卷（使用默认StorageClass）

### 存储配置
- NameNode存储: 10Gi ReadWriteOnce
- DataNode存储: 20Gi ReadWriteOnce
- 使用默认StorageClass进行自动存储卷管理

### 部署命令
```bash
# 安装chart
helm install hadoop-cluster ./

# 升级现有部署
helm upgrade hadoop-cluster ./

# 卸载
helm uninstall hadoop-cluster
```

### 访问方式
- NameNode Web UI: `http://<pod-ip>:9870`
- DataNode Web UI: `http://<pod-ip>:9864`
- HDFS RPC: `hdfs://<namenode-pod>:9000`

### 注意事项
1. 确保集群有足够的存储资源
2. 确保有默认的StorageClass
3. 多namenode模式下，只有第一个namenode会进行格式化
4. DataNode会自动连接到可用的NameNode

## 配置参数

主要配置参数在 `values.yaml` 中：

```yaml
hdfs:
  nameNode:
    replicas: 3
  dataNode:
    replicas: 3
  replication: 3

persistence:
  nameNode:
    enabled: true
    size: "10Gi"
  dataNode:
    enabled: true
    size: "20Gi"
```
