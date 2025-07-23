FROM centos:7.9.2009

RUN rm -f /etc/localtime && ln -sv /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && echo "Asia/Shanghai" > /etc/timezone
# 使用阿里云镜像源替代失效的官方源
RUN mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.backup && \
    curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo && \
    sed -i -e '/mirrors.cloud.aliyuncs.com/d' -e '/mirrors.aliyuncs.com/d' /etc/yum.repos.d/CentOS-Base.repo && \
    yum clean all && \
    yum makecache
# 安装基础组件
RUN yum -y install net-tools telnet make wget nc expect which vim telnet

RUN mkdir /opt/hadoop

ENV HADOOP_HOME=/opt/hadoop
ENV HADOOP_COMMON_HOME=${HADOOP_HOME}
ENV HADOOP_HDFS_HOME=${HADOOP_HOME}
ENV HADOOP_CONF_DIR=${HADOOP_HOME}/etc/hadoop
ENV PATH=${PATH}:${HADOOP_HOME}/bin

# 安装 JDK
ADD jdk-8u451-linux-x64.tar.gz ${HADOOP_HOME}
ENV JAVA_HOME=${HADOOP_HOME}/jdk1.8.0_212
ENV PATH=$JAVA_HOME/bin:$PATH
ENV ll="ls -l"

# 配置 Hadoop
ENV HADOOP_VERSION 3.3.6
ADD hadoop-${HADOOP_VERSION}.tar.gz /opt
RUN ln -s /opt/hadoop-${HADOOP_VERSION} $HADOOP_HOME

WORKDIR $HADOOP_HOME