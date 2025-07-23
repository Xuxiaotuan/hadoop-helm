```markdown
# Hadoop HDFS 集群（Kubernetes 部署方案）

## 项目概述
本项目提供一套基于 Kubernetes（K8s）的 Hadoop HDFS 集群完整部署方案，通过 Helm Chart 实现自动化编排与管理。方案聚焦高可用性、数据可靠性和运维便捷性，支持 NameNode 自动故障转移、数据持久化存储及外部便捷访问，适用于生产环境的分布式数据存储场景。


## 核心优势
- **高可用架构**：采用双副本 NameNode（Active/Standby 模式）+ 3 副本 JournalNode 实现元数据高可用，结合 ZooKeeper 完成自动故障转移。
- **数据安全保障**：通过 PersistentVolumeClaim（PVC）持久化存储 NameNode 元数据、DataNode 数据和 JournalNode 日志，避免 Pod 重启导致数据丢失。
- **智能调度策略**：利用 K8s 反亲和性配置，确保核心组件（NN/JN/DN）分散在不同节点，降低单点故障风险。
- **自动化运维**：内置启动脚本实现组件初始化、状态监控及标签动态更新，无需人工干预活跃节点标识。
- **灵活访问控制**：提供 Ingress 配置，支持外部通过自定义域名访问 NameNode WebUI，简化集群管理。


## 组件架构
HDFS 集群在 K8s 环境中的核心组件及功能如下：

| 组件           | 功能描述                                                                 | 部署方式               | 关键参数（`values.yaml`）                  |
|----------------|--------------------------------------------------------------------------|------------------------|--------------------------------------------|
| NameNode（NN） | 管理文件系统元数据，协调集群操作，分为 Active 和 Standby 两个角色         | StatefulSet（2 副本）  | `hdfs.nameNode.replicas=2`                 |
| JournalNode（JN） | 同步 NameNode 编辑日志，通过多数派机制确保元数据一致性                     | StatefulSet（≥3 副本） | `hdfs.journalNode.replicas=3`              |
| DataNode（DN） | 存储实际数据块，处理客户端读写请求，执行数据复制与校验                     | StatefulSet（≥3 副本） | `hdfs.dataNode.replicas=3`                 |
| ZKFC           | 依赖 ZooKeeper 监控 NameNode 状态，触发自动故障转移                       | 嵌入 NN 容器           | `hdfs.nameNode.zookeeperQuorum`            |
| Ingress        | 外部访问 NameNode WebUI 的入口，映射自定义域名到 Active NN                | Ingress 资源           | `spec.rules[0].host=ssc-hn.hdfs.webui.com` |
| RBAC 资源      | 包含 ServiceAccount、Role 和 RoleBinding，授权 NN 修改自身状态标签         | 独立资源配置           | -                                          |


## 部署环境要求
### 基础环境
- **Kubernetes 集群**：v1.21 及以上版本，节点数量 ≥ 3（推荐 5+ 节点以满足反亲和性调度）。
- **Helm 客户端**：v3.0 及以上，用于部署和管理 Helm Chart。
- **ZooKeeper 集群**：3 节点及以上（用于 NN 自动故障转移），需提供节点访问地址（格式：`zk-0:2181,zk-1:2181,zk-2:2181`）。
- **存储类（StorageClass）**：需支持 `ReadWriteOnce` 访问模式，用于创建 PVC 实现数据持久化。

### 网络与权限
- **内部网络**：集群内 Pod 间需网络互通（NN 与 JN、DN 与 NN、JN 节点间需通信）。
- **外部访问**：若启用 Ingress，需提前配置 DNS 解析（将自定义域名映射到 K8s 集群入口 IP）。
- **权限要求**：部署用户需具备 K8s 集群的 `cluster-admin` 权限（用于创建 RBAC 资源和命名空间）。


## 快速部署指南
### 步骤 1：准备配置文件
创建 `values.yaml` 文件，根据实际环境自定义配置（以下为核心配置示例）：
```yaml
# 镜像配置（需包含 Hadoop 3.x 及依赖组件）
image:
  repository: your-registry/hadoop
  tag: 3.3.4
  pullPolicy: IfNotPresent

# 反亲和性策略（生产环境推荐 hard，强制组件分散在不同节点）
antiAffinity: hard

# HDFS 核心配置
hdfs:
  clusterName: my-hdfs-cluster  # 集群逻辑名称（需与 core-site.xml 保持一致）
  nameNode:
    zookeeperQuorum: "zk-0:2181,zk-1:2181,zk-2:2181"  # ZooKeeper 集群地址
    resources:  # 资源限制（根据节点配置调整）
      requests:
        cpu: 1000m
        memory: 2Gi
      limits:
        cpu: 2000m
        memory: 4Gi
  dataNode:
    replicas: 3  # DataNode 副本数（建议 ≥3，与 dfs.replication 一致）
    resources:
      requests:
        cpu: 500m
        memory: 1Gi
  journalNode:
    replicas: 3  # JournalNode 副本数（必须为奇数，≥3）

# 持久化存储配置（生产环境必须启用）
persistence:
  nameNode:
    enabled: true
    storageClass: "hdfs-nn-storage"  # 存储类名称
    size: 10Gi  # 元数据存储大小
  dataNode:
    enabled: true
    storageClass: "hdfs-dn-storage"
    size: 100Gi  # 数据存储大小（根据需求调整）
  journalNode:
    enabled: true
    storageClass: "hdfs-jn-storage"
    size: 20Gi  # 日志存储大小

# 日志级别（默认 INFO，调试时可改为 DEBUG）
logLevel: INFO
```

### 步骤 2：部署集群
1. **创建命名空间**（可选，推荐独立命名空间隔离资源）：
   ```bash
   kubectl create namespace hdfs
   ```

2. **使用 Helm 部署**：
   ```bash
   helm install hdfs-cluster ./hadoop \
     -f values.yaml \
     --namespace hdfs
   ```
   - 若需覆盖默认配置，可通过 `--set` 参数临时修改（如 `--set hdfs.dataNode.replicas=4`）。

3. **验证部署状态**：
   ```bash
   # 查看所有组件 Pod 状态（应均为 Running）
   kubectl get pods -n hdfs -o wide

   # 查看 StatefulSet 状态（确认副本数与配置一致）
   kubectl get statefulset -n hdfs

   # 查看 Active NameNode（通过标签筛选）
   kubectl get pods -n hdfs -l hdfs.nn.state=active
   ```


## 集群访问与验证
### 访问 NameNode WebUI
1. **配置 DNS 解析**：将自定义域名（如 `ssc-hn.hdfs.webui.com`）映射到 K8s 集群 Ingress 控制器的外部 IP。
2. **通过浏览器访问**：`http://ssc-hn.hdfs.webui.com`（默认端口 80，若需指定端口可在 Ingress 配置中添加）。
3. **验证内容**：WebUI 首页应显示集群状态（如总容量、已用空间、DataNode 数量等）。

### 执行 HDFS 命令
1. **进入 NameNode 容器**：
   ```bash
   kubectl exec -it -n hdfs hdfs-cluster-hdfs-nn-0 -- bash
   ```

2. **执行测试命令**：
   ```bash
   # 查看集群报告
   hdfs dfsadmin -report

   # 创建测试目录
   hdfs dfs -mkdir /test

   # 上传文件
   echo "hello hdfs" > test.txt
   hdfs dfs -put test.txt /test/

   # 验证文件存在
   hdfs dfs -ls /test/
   ```


## 日常运维操作
### 组件管理
- **重启组件**：
  ```bash
  # 重启 NameNode
  kubectl rollout restart statefulset/hdfs-cluster-hdfs-nn -n hdfs

  # 重启 DataNode
  kubectl rollout restart statefulset/hdfs-cluster-hdfs-dn -n hdfs
  ```

- **查看日志**：
  ```bash
  # 查看 NameNode 日志（最后 100 行）
  kubectl logs -n hdfs hdfs-cluster-hdfs-nn-0 --tail=100

  # 实时查看 JournalNode 日志
  kubectl logs -n hdfs hdfs-cluster-hdfs-jn-0 -f
  ```

- **扩容 DataNode**：
   1. 修改 `values.yaml` 中 `hdfs.dataNode.replicas` 为目标数量（如 5）。
   2. 执行 Helm 升级命令：
      ```bash
      helm upgrade hdfs-cluster ./hadoop -f values.yaml -n hdfs
      ```

### 故障转移测试
1. **手动触发故障转移**：
   ```bash
   # 删除当前 Active NameNode Pod
   kubectl delete pod -n hdfs <active-nn-pod-name>
   ```

2. **验证切换结果**：
   ```bash
   # 等待约 30 秒后，查看新的 Active NameNode
   kubectl get pods -n hdfs -l hdfs.nn.state=active
   ```
   - 预期结果：原 Standby NameNode 应切换为 Active，WebUI 访问自动指向新节点。


## 卸载集群
1. **卸载 Helm 发布**（保留 PVC 数据）：
   ```bash
   helm uninstall hdfs-cluster -n hdfs
   ```

2. **彻底清理数据**（如需删除所有持久化数据）：
   ```bash
   # 删除所有 PVC（谨慎操作，数据将永久丢失）
   kubectl delete pvc -n hdfs --all

   # 删除命名空间
   kubectl delete namespace hdfs
   ```


## 注意事项
1. **数据持久化**：
   - 生产环境必须启用 `persistence.enabled=true`，否则 Pod 重建后元数据和用户数据将丢失。
   - 存储类需支持 `ReadWriteOnce` 访问模式（NN/JN/DN 均需独占存储）。

2. **版本兼容性**：
   - Hadoop 3.x 与 2.x 端口存在差异（如 JN 数据同步端口 3.x 为 8485，2.x 为 8480），需确保镜像版本与配置文件中的端口一致。
   - 若使用自定义 Hadoop 镜像，需确保内置 `bootstrap.sh` 脚本与本方案兼容。

3. **资源配置**：
   - NameNode 和 JournalNode 为核心组件，建议配置较高的内存（如 2Gi+），避免 OOM 导致服务中断。
   - DataNode 资源配置需根据节点数据量和读写负载调整，CPU 不足会导致数据处理延迟。

4. **安全建议**：
   - 生产环境可启用 HDFS 权限控制（如设置文件系统 ACL），并限制 Pod 访问权限。
   - 定期备份 NameNode 元数据（通过 `hdfs dfsadmin -saveNamespace`），防止数据损坏。

5. **监控与告警**：
   - 推荐集成 Prometheus + Grafana 监控集群指标（如 NN 堆内存使用率、DN 磁盘使用率、块丢失数量等）。
   - 配置告警规则（如 Pod 异常重启、磁盘使用率超过 80%），及时响应集群问题。


## 常见问题排查
1. **Pod 启动失败**：
   - 检查事件：`kubectl describe pod <pod-name> -n hdfs`，排查存储挂载失败、镜像拉取错误等问题。
   - 查看日志：`kubectl logs <pod-name> -n hdfs`，定位初始化脚本错误（如配置文件缺失、权限不足）。

2. **DataNode 无法注册到 NameNode**：
   - 检查网络连通性：`kubectl exec -n hdfs <dn-pod> -- ping <nn-service-name>`。
   - 验证配置：确保 `hdfs-site.xml` 中 `dfs.namenode.rpc-address` 指向正确的 NameNode 服务。

3. **故障转移失败**：
   - 检查 ZooKeeper 集群状态：确保所有 ZK 节点正常运行且 NN 能访问。
   - 查看 ZKFC 日志：`kubectl logs <nn-pod> -n hdfs | grep zkfc`，排查连接 ZK 失败或状态切换错误。


## 版本历史
| 版本 | 日期       | 变更说明                     |
|------|------------|------------------------------|
| v1.0 | 2025-70-01 | 初始版本，支持 Hadoop 3.3.6  |

## 联系方式
- 维护团队：大数据平台组
- 联系邮箱：bjwanyi@foxmail.com
- 问题反馈：请提交 Issue 至本项目代码仓库
```