# PQ-GM-IPSec & IKEv2 - Docker 测试环境基础镜像
# strongSwan 6.0.4 从源码编译
FROM ubuntu:22.04

# 避免交互式提示
ENV DEBIAN_FRONTEND=noninteractive

# 安装编译依赖
RUN apt-get update && apt-get install -y \
    build-essential \
    autoconf \
    automake \
    libtool \
    pkg-config \
    bison \
    flex \
    gperf \
    libssl-dev \
    libgmp-dev \
    libpam0g-dev \
    libsqlite3-dev \
    libxml2-dev \
    libxslt1-dev \
    libnl-3-dev \
    libnl-genl-3-dev \
    libnl-route-3-dev \
    libkrb5-dev \
    libldap2-dev \
    libcurl4-openssl-dev \
    libjson-c-dev \
    libpcre2-dev \
    python3-dev \
    iproute2 \
    iptables \
    iputils-ping \
    tcpdump \
    strace \
    vim \
    curl \
    && rm -rf /var/lib/apt/lists/*

# 复制本地 strongSwan 源码
COPY strongswan-6.0.4.tar.gz /tmp/

# 解压并编译 strongSwan
WORKDIR /tmp
RUN tar -xzf strongswan-6.0.4.tar.gz \
    && cd strongswan-6.0.4 \
    && ./autogen.sh \
    && ./configure \
        --prefix=/usr \
        --sysconfdir=/etc \
        --enable-swanctl \
        --enable-vici \
        --enable-systime-fix \
        --enable-shared \
        --disable-static \
        --with-libpcre2 \
    && make -j$(nproc) \
    && make install \
    && ldconfig \
    && cd / \
    && rm -rf /tmp/strongswan*

# 创建必要的目录
RUN mkdir -p /etc/swanctl \
    && mkdir -p /var/run/swanctl \
    && mkdir -p /tests/data/{pcaps,logs,configs_snapshot} \
    && mkdir -p /etc/strongswan.d

# 创建 strongswan.conf (使用 printf 避免转义问题)
RUN printf 'charon {\n    debug = 4\n}\nswanctl {\n    load = pki,vici,stroke\n}\n' > /etc/strongswan.conf

# 设置工作目录
WORKDIR /project

# 验证安装
RUN swanctl --version || true

CMD ["/bin/bash"]
