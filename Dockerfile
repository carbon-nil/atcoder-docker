FROM ubuntu:24.04

ENV TZ=Asia/Tokyo \
    DEBIAN_FRONTEND=noninteractive

RUN apt update && \
    apt install -y --no-install-recommends time wget unzip git curl ca-certificates cmake && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

# C++
RUN apt update && \
    apt install -y --no-install-recommends \
        build-essential \
        gcc-14 \
        g++-14 \
        gdb \
        libabsl-dev \
        libboost-all-dev \
        libeigen3-dev \
        libgmp-dev \
        libz3-dev && \
    apt clean && rm -rf /var/lib/apt/lists/*
WORKDIR /opt
RUN git clone --depth 1 -b v1.6 https://github.com/atcoder/ac-library.git /lib/ac-library && \
    wget https://gitlab.com/libeigen/eigen/-/archive/3.4.0/eigen-3.4.0.tar.gz && \
    tar -xf eigen-3.4.0.tar.gz -C /usr/local/include --strip-components=1 && \
    git clone --depth 1 https://github.com/arximboldi/immer.git && \
    cp -r immer/immer /usr/local/include/ && \
    git clone --depth 1 -b 0.12.0 https://github.com/ericniebler/range-v3.git && \
    cp -r range-v3/include/* /usr/local/include/ && \
    git clone --depth 1 https://github.com/martinus/unordered_dense.git && \
    cp unordered_dense/include/ankerl/unordered_dense.h /usr/local/include/
RUN git clone --depth 1 -b 20250512.1 https://github.com/abseil/abseil-cpp.git && \
    cd abseil-cpp && mkdir build && cd build && \
    cmake .. -DCMAKE_CXX_STANDARD=20 -DCMAKE_INSTALL_PREFIX=/usr/local && \
    make -j$(nproc) install
RUN git clone --recursive --depth 1 https://github.com/microsoft/LightGBM && \
    cd LightGBM && mkdir build && cd build && \
    cmake .. && make -j$(nproc)
RUN wget https://download.pytorch.org/libtorch/cpu/libtorch-shared-with-deps-2.8.0%2Bcpu.zip && \
    unzip libtorch-shared-with-deps-2.8.0+cpu.zip && \
    rm libtorch-shared-with-deps-2.8.0+cpu.zip
RUN wget https://github.com/google/or-tools/releases/download/v9.14/or-tools_x86_64_ubuntu-24.04_cpp_v9.14.6206.tar.gz && \
    tar -xf oor-tools_x86_64_ubuntu-24.04_cpp_v9.14.6206.tar.gz && \
    cp -r or-tools_x86_64_ubuntu-24.04_cpp_v9.14.6206/include/* /usr/local/include/ && \
    cp -r or-tools_x86_64_ubuntu-24.04_cpp_v9.14.6206/lib/* /usr/local/lib/
ENV CXX=g++-14 \
    CC=gcc-14 \
    CPLUS_INCLUDE_PATH="/usr/local/include:/lib/ac-library:/opt/libtorch/include:/opt/libtorch/include/torch/csrc/api/include" \
    LIBRARY_PATH="/usr/local/lib:/opt/libtorch/lib" \
    LD_LIBRARY_PATH="/usr/local/lib:/opt/libtorch/lib"

# Python
RUN apt update && \
    apt install -y --no-install-recommends \
        python3.12 \
        python3-pip \
        python3-setuptools \
        python3-dev && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir --break-system-packages \
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
    /root/.cargo/bin/rustup component add rust-src && \
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
