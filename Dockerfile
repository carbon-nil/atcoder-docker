FROM ubuntu:24.04 AS base-toolchain

ENV TZ=Asia/Tokyo \
    DEBIAN_FRONTEND=noninteractive

RUN apt update && \
    apt install -y --no-install-recommends time wget unzip git curl ca-certificates cmake && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

# Light version
FROM base-toolchain AS light

# C++
RUN apt update && \
    apt install -y --no-install-recommends \
        build-essential \
        gcc-14 \
        g++-14 \
        gdb && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 -b v1.6 https://github.com/atcoder/ac-library.git /lib/ac-library
ENV CXX=g++-14 \
    CC=gcc-14 \
    CPLUS_INCLUDE_PATH="/usr/local/include:/lib/ac-library"

# Python
RUN apt update && \
    apt install -y --no-install-recommends \
        python3.12 \
        python3-pip \
        python3-setuptools \
        python3-dev && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*
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
RUN pip3 install --no-cache-dir --break-system-packages online-judge-tools aclogin
RUN npm install -g atcoder-cli && \
    npm cache clean --force && \
    acc config default-test-dirname-format test

# Full version
FROM light AS full
WORKDIR /opt

# C++ Library
RUN apt update && \
    apt install -y --no-install-recommends \
        libabsl-dev \
        libboost-all-dev \
        libeigen3-dev \
        libgmp-dev \
        libz3-dev && \
    apt clean && rm -rf /var/lib/apt/lists/*
RUN wget https://gitlab.com/libeigen/eigen/-/archive/3.4.0/eigen-3.4.0.tar.gz && \
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
RUN wget -O or-tools.tar.gz "https://github.com/google/or-tools/releases/download/v9.14/or-tools_amd64_ubuntu-24.04_cpp_v9.14.6206.tar.gz" && \
    tar -xf or-tools.tar.gz && \
    cp -r or-tools_*/include/* /usr/local/include/ && \
    cp -r or-tools_*/lib/* /usr/local/lib/ && \
    rm -rf or-tools.tar.gz or-tools_*
ENV CPLUS_INCLUDE_PATH="/usr/local/include:/lib/ac-library:/opt/libtorch/include:/opt/libtorch/include/torch/csrc/api/include" \
    LD_LIBRARY_PATH="/usr/local/lib:/opt/libtorch/lib"

# Python Library
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

# Rust Library
RUN cargo new --lib /opt/rust-warmup
WORKDIR /opt/rust-warmup
COPY <<EOF Cargo.toml
[package]
name = "rust-warmup"
version = "0.1.0"
edition = "2021"

[dependencies]
ac-library-rs = "0.2.0"
alga = "0.9.3"
amplify = "4.9.0"
amplify_derive = "4.0.1"
amplify_num = "0.5.3"
argio = "0.2.0"
ascii = "1.1.0"
az = "1.2.1"
bitset-fixed = "0.1.0"
bitvec = "1.0.1"
bstr = "1.12.0"
btreemultimap = "0.1.1"
counter = "0.7.0"
easy-ext = "1.0.2"
either = "1.15.0"
fixedbitset = "0.5.7"
getrandom = "0.3.3"
glidesort = "0.1.2"
hashbag = "0.1.12"
im-rc = "15.1.0"
indexing = "0.4.1"
indexmap = "2.11.0"
itertools = "0.14.0"
itertools-num = "0.1.3"
lazy_static = "1.5.0"
libm = "0.2.15"
maplit = "1.0.2"
memoise = "0.3.2"
multimap = "0.10.1"
multiversion = "0.8.0"
nalgebra = "0.34.0"
ndarray = "0.16.1"
num = "0.4.3"
num-bigint = "0.4.6"
num-complex = "0.4.6"
num-derive = "0.4.2"
num-integer = "0.1.46"
num-iter = "0.1.45"
num-rational = "0.4.2"
num-traits = "0.2.19"
omniswap = "0.1.0"
once_cell = "1.21.3"
ordered-float = "5.0.0"
pathfinding = "4.14.0"
permutohedron = "0.2.4"
petgraph = "0.8.2"
primal = "0.3.3"
proconio = "0.5.0"
rand = "0.9.2"
rand_chacha = "0.9.0"
rand_core = "0.9.3"
rand_distr = "0.5.1"
rand_hc = "0.4.0"
rand_pcg = "0.9.0"
rand_xorshift = "0.4.0"
rand_xoshiro = "0.7.0"
recur-fn = "2.2.0"
regex = "1.11.2"
rpds = "1.1.1"
rustc-hash = "2.1.1"
smallvec = "1.15.1"
static_assertions = "1.1.0"
statrs = "0.18.0"
superslice = "1.0.0"
tap = "1.0.1"
text_io = "0.1.13"
thiserror = "2.0.16"
varisat = "0.2.2"
EOF
RUN cargo build --release && rm -rf /opt/rust-warmup

# Workspace
WORKDIR /workspace

CMD ["/bin/bash"]
