# PQ-GM-IPSec & IKEv2 - Docker 测试环境基础镜像
FROM ubuntu:22.04

# 避免交互式提示
ENV DEBIAN_FRONTEND=noninteractive

# 安装基础依赖和 strongSwan
RUN apt-get update && apt-get install -y \
    build-essential \
    autoconf \
    automake \
    libtool \
    pkg-config \
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
    python3-dev \
    python3-pip \
    iproute2 \
    iptables \
    iputils-ping \
    tcpdump \
    strace \
    gdb \
    vim \
    wget \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# 安装 strongSwan (从 Ubuntu 仓库获取基础版本，后续用编译版本替换)
RUN apt-get update && apt-get install -y \
    strongswan \
    strongswan-swanctl \
    strongswan-starter \
    strongswan-pki \
    libcharon-extra-plugins \
    libstrongswan-extra-plugins \
    && rm -rf /var/lib/apt/lists/*

# 创建必要的目录
RUN mkdir -p /etc/swanctl \
    && mkdir -p /var/run/swanctl \
    && mkdir -p /tests/data/{pcaps,logs,configs_snapshot}

# 设置调试日志级别
RUN sed -i 's/#charondebug="ike 1, knl 1, cfg 0"/charondebug="ike 4, knl 4, cfg 4, net 4, esp 4, lib 4"/' /etc/strongswan.conf || true

# 创建工作目录
WORKDIR /project

# 默认命令
CMD ["/bin/bash"]
