# 使用官方 CentOS 7.9 作为基础镜像
FROM centos:7.9.2009

# 镜像作者信息
LABEL maintainer="jia_yangchen@163.com"
LABEL version="3.3.6"
LABEL description="Hadoop 3.3.6 镜像，适用于 macOS ARM 的单机 Kubernetes 环境"

# 设置环境变量
ENV JAVA_HOME=/opt/jdk1.8.0_461 \
    HADOOP_VERSION=3.3.6 \
    HADOOP_HOME=/opt/hadoop \
    HADOOP_CONF_DIR=/opt/hadoop/etc/hadoop \
    PATH=$PATH:/opt/hadoop/bin:/opt/hadoop/sbin:/opt/jdk1.8.0_461/bin

# 设置时区 + 替换为 USTC YUM 源（适配 ARM 架构）+ 安装工具
RUN rm -f /etc/localtime && \
    ln -sv /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone && \
    curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.ustc.edu.cn/repofile/centos-7.repo && \
    sed -i 's|^mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/CentOS-Base.repo && \
    sed -i 's|^#baseurl=http://mirror.centos.org|baseurl=http://mirrors.ustc.edu.cn|g' /etc/yum.repos.d/CentOS-Base.repo && \
    yum clean all && \
    yum makecache fast && \
    yum install -y --setopt=install_weak_deps=false \
        net-tools \
        telnet \
        wget \
        nc \
        openssh-clients \
        vim \
        which && \
    yum clean all && \
    rm -rf /var/cache/yum/*


# 添加并解压 JDK（请确保 jdk-8u461-linux-x64.tar.gz 与 Dockerfile 同目录）
ADD jdk-8u461-linux-x64.tar.gz /opt/
RUN chmod -R 755 ${JAVA_HOME}

# 添加并解压 Hadoop（请确保 hadoop-3.3.6.tar.gz 与 Dockerfile 同目录）
ADD hadoop-3.3.6.tar.gz /opt/
RUN ln -s /opt/hadoop-${HADOOP_VERSION} ${HADOOP_HOME} && \
    chmod -R 755 ${HADOOP_HOME}

# 创建 hadoop 用户，避免使用 root 启动服务
RUN groupadd hadoop && \
    useradd -g hadoop hadoop && \
    chown -R hadoop:hadoop ${HADOOP_HOME} ${JAVA_HOME}

# 使用非 root 用户启动
USER hadoop
WORKDIR ${HADOOP_HOME}

# 容器启动后默认执行 bash
CMD ["/bin/bash"]
