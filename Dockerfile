FROM ubuntu:24.04

ENV TZ=Asia/Tokyo \
    DEBIAN_FRONTEND=noninteractive

RUN apt update && \
    apt install -y --no-install-recommends time unzip git curl ca-certificates && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

# C++
RUN apt update && \
    apt install -y --no-install-recommends \
        build-essential \
        gcc-14 \
        g++-14 \
        gdb && \
    apt clean && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 -b v1.6 https://github.com/atcoder/ac-library.git /lib/ac-library
ENV CPLUS_INCLUDE_PATH=/lib/ac-library

# Python
RUN apt update && \
    apt install -y --no-install-recommends \
        python3 \
        python3-pip \
        python3-setuptools && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir \
        numpy \
        scipy \
        pandas \
        scikit-learn \
        networkx \
        PuLP \
        bitarray \
        more-itertools \
        mpmath \
        shapely \
        sortedcontainers \
        sympy \
        z3-solver \
        ac-library-python \
        acl-cpp-python \
        cppyy
ENV PYTHONUNBUFFERED=1

# Rust
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain stable --profile minimal && \
    rustup component add rust-src && \
    rm -rf /root/.rustup/toolchains/*/share/doc /root/.cargo/registry/cache
ENV PATH="/root/.cargo/bin:${PATH}"

# Library
RUN apt update && \
    apt install -y --no-install-recommends \
        nodejs \
        npm && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*
RUN pip3 install --no-cache-dir --break-system-packages online-judge-tools
RUN npm install -g atcoder-cli && \
    npm cache clean --force && \
    acc config default-test-dirname-format test

# Workspace
WORKDIR /workspace
