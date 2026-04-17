FROM ubuntu:24.04

ENV TZ=Asia/Tokyo
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN apt update && apt install -y \
    build-essential \
    gdb \
    python3-pip \
    nodejs \
    npm \
    git \
    curl \
    wget \
    unzip \
    && apt clean

# C++
WORKDIR /opt
RUN git clone https://github.com/atcoder/ac-library.git
ENV CPLUS_INCLUDE_PATH /opt/ac-library

# online-judge-tools
RUN pip install online-judge-tools

# atcoder-cli
RUN npm install -g atcoder-cli

# workspace
WORKDIR /workspace
