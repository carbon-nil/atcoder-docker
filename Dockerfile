FROM ubuntu:24.04 AS base-toolchain

ENV TZ=Asia/Tokyo \
    DEBIAN_FRONTEND=noninteractive

RUN apt update && \
    apt install -y --no-install-recommends time wget unzip git curl ca-certificates cmake && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

# Light version
FROM base-toolchain AS light

ARG TARGETARCH

# C++
# GCC 15.2.0 は Ubuntu 24.04 向けにビルドされた toolchain PPA から入れる (AtCoder も 24.04 上でビルドしている)
RUN apt update && \
    apt install -y --no-install-recommends software-properties-common && \
    add-apt-repository -y ppa:ubuntu-toolchain-r/test && \
    apt install -y --no-install-recommends \
        build-essential \
        gcc-15 \
        g++-15 \
        gdb && \
    ln -s /usr/bin/gcc-15 /usr/local/bin/gcc && \
    ln -s /usr/bin/g++-15 /usr/local/bin/g++ && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 -b v1.6 https://github.com/atcoder/ac-library.git /lib/ac-library
ENV CXX=g++ \
    CC=gcc \
    CPLUS_INCLUDE_PATH="/usr/local/include:/lib/ac-library"

# Python
RUN apt update && \
    apt install -y --no-install-recommends \
        python3.12 \
        python3-pip \
        python3-setuptools \
        python3-dev \
        bzip2 && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*
ENV PYTHONUNBUFFERED=1
COPY --from=ghcr.io/astral-sh/uv:0.8.22 /uv /usr/local/bin/uv
ENV UV_PYTHON_INSTALL_DIR=/opt/python
RUN uv python install 3.13.7 && \
    ln -s "$(uv python find --managed-python 3.13.7)" /usr/local/bin/python3.13 && \
    python3.13 -m pip --version

# PyPy
RUN case "$TARGETARCH" in \
        amd64) pypy_arch=linux64 ;; \
        arm64) pypy_arch=aarch64 ;; \
        *) echo "Unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac && \
    wget -O /tmp/pypy.tar.bz2 "https://downloads.python.org/pypy/pypy3.11-v7.3.20-${pypy_arch}.tar.bz2" && \
    mkdir -p /opt/pypy && \
    tar -xjf /tmp/pypy.tar.bz2 -C /opt/pypy --strip-components=1 && \
    rm /tmp/pypy.tar.bz2 && \
    ln -s /opt/pypy/bin/pypy3 /usr/local/bin/pypy3 && \
    pypy3 -m ensurepip

# Rust
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain 1.89.0 --profile minimal && \
    /root/.cargo/bin/rustup component add rust-src && \
    rm -rf /root/.rustup/toolchains/*/share/doc /root/.cargo/registry/cache
ENV PATH="/root/.cargo/bin:${PATH}"
COPY <<'EOF' /root/.cargo/config.toml
[build]
rustflags = ["--cfg", "atcoder"]
EOF

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

# Command
COPY <<'EOF' /usr/local/bin/ojt
#!/bin/bash
python=python3.13
if [ "${1:-}" = pypy ]; then
    python=pypy3
    shift
fi

if [ -f main.cpp ]; then
    g++ -std=gnu++23 -O2 -Wall -Wextra -march=native -pthread \
        -fconstexpr-depth=1024 -fconstexpr-loop-limit=524288 \
        -fconstexpr-ops-limit=2097152 -ftrivial-auto-var-init=zero \
        -U_FORTIFY_SOURCE -fno-stack-protector -fno-stack-clash-protection -fcf-protection=none -no-pie \
        -DATCODER -DONLINE_JUDGE main.cpp -o a.out && oj t -c ./a.out "$@"
elif [ -f main.py ]; then
    oj t -c "$python -X int_max_str_digits=0 main.py" "$@"
elif [ -f main.rs ]; then
    if [ -f Cargo.toml ]; then
        cargo build --release && oj t -c "./target/release/$(basename "$PWD")" "$@"
    else
        rustc -O main.rs -o a.out && oj t -c ./a.out "$@"
    fi
else
    echo "Error: main.cpp, main.py, or main.rs not found." >&2
    exit 1
fi
EOF
RUN chmod +x /usr/local/bin/ojt

# Full version
FROM light AS full
ARG TARGETARCH
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
RUN git clone --depth 1 https://github.com/arximboldi/immer.git && \
    cp -r immer/immer /usr/local/include/ && \
    git clone --depth 1 -b 0.12.0 https://github.com/ericniebler/range-v3.git && \
    cp -r range-v3/include/* /usr/local/include/ && \
    git clone --depth 1 https://github.com/martinus/unordered_dense.git && \
    cp unordered_dense/include/ankerl/unordered_dense.h /usr/local/include/
RUN git clone --depth 1 -b 20250512.1 https://github.com/abseil/abseil-cpp.git && \
    cd abseil-cpp && mkdir build && cd build && \
    cmake .. -DCMAKE_CXX_STANDARD=20 -DCMAKE_INSTALL_PREFIX=/usr/local && \
    make -j$(nproc) install
# リリースの tarball は submodule (eigen など) を同梱しているので、GitLab から取らずに済む
# tarball の Python パッケージ lightgbm/ が CLI の出力先と衝突するので、AtCoder と同じくライブラリだけをビルドする
RUN wget -O lightgbm.tar.gz https://github.com/microsoft/LightGBM/releases/download/v4.6.0/lightgbm-4.6.0.tar.gz && \
    mkdir LightGBM && tar -xf lightgbm.tar.gz -C LightGBM --strip-components=1 && rm lightgbm.tar.gz && \
    cd LightGBM && mkdir build && cd build && \
    cmake -DBUILD_CLI=OFF .. && make -j$(nproc)
# arm64 向けの libtorch は配布されていないので、torch の wheel から include と lib を取り出す
# (wheel の lib は rpath で ../../torch.libs を参照するので、/opt に展開してから libtorch に改名する)
RUN case "$TARGETARCH" in \
        amd64) \
            wget -O libtorch.zip https://download.pytorch.org/libtorch/cpu/libtorch-shared-with-deps-2.8.0%2Bcpu.zip && \
            unzip -q libtorch.zip ;; \
        arm64) \
            wget -O libtorch.zip https://download.pytorch.org/whl/cpu/torch-2.8.0%2Bcpu-cp313-cp313-manylinux_2_28_aarch64.whl && \
            unzip -q libtorch.zip 'torch/include/*' 'torch/lib/*' 'torch/share/*' 'torch.libs/*' && \
            mv torch libtorch ;; \
        *) echo "Unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac && \
    rm libtorch.zip
RUN case "$TARGETARCH" in \
        amd64) or_tools=or-tools_amd64_ubuntu-24.04_cpp_v9.14.6206 ;; \
        arm64) or_tools=or-tools_aarch64_AlmaLinux-8.10_cpp_v9.14.6206 ;; \
        *) echo "Unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac && \
    wget -O or-tools.tar.gz "https://github.com/google/or-tools/releases/download/v9.14/${or_tools}.tar.gz" && \
    tar -xf or-tools.tar.gz && \
    cp -r or-tools_*/include/* /usr/local/include/ && \
    cp -r or-tools_*/lib*/* /usr/local/lib/ && \
    rm -rf or-tools.tar.gz or-tools_*
ENV CPLUS_INCLUDE_PATH="/usr/local/include:/lib/ac-library:/usr/include/eigen3:/opt/libtorch/include:/opt/libtorch/include/torch/csrc/api/include" \
    LD_LIBRARY_PATH="/usr/local/lib:/opt/libtorch/lib"

# Python Library
RUN python3.13 -m pip install --no-cache-dir --break-system-packages \
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
        acl-cpp-python
# cppyy は AtCoder と同じ組み合わせに固定する。arm64 には cppyy-cling の wheel がなくソースからビルドになるが、
# pip の隔離ビルドは最新の cmake (4 系) を入れて設定に失敗するので、隔離せずにシステムの cmake (3.28) を使う
# 同梱の LLVM は GCC 14.3 以降だと C++20 でコンパイルできない (root-project/root#18939) ので、ビルドだけ g++-13 で行う
RUN python3.13 -m pip install --no-cache-dir --break-system-packages setuptools wheel && \
    for p in cppyy-cling==6.32.8 cppyy-backend==1.15.3 cppyy==3.5.0; do \
        CC=gcc-13 CXX=g++-13 python3.13 -m pip install --no-cache-dir --break-system-packages --no-build-isolation "$p" || exit 1; \
    done && \
    python3.13 -c "import cppyy; cppyy.cppdef('int one() { return 1; }'); assert cppyy.gbl.one() == 1"

# Rust Library
# AtCoder と同じ Cargo.toml / Cargo.lock (rust-lang-ja/atcoder-proposal、AtCoder のインストールスクリプトと同じコミット) で依存をビルドしておく
WORKDIR /opt/rust-warmup
RUN curl -fsS --remote-name-all \
        https://raw.githubusercontent.com/rust-lang-ja/atcoder-proposal/7a724cdf84202ce3bef84527676e2c398bca7b6e/Cargo.toml \
        https://raw.githubusercontent.com/rust-lang-ja/atcoder-proposal/7a724cdf84202ce3bef84527676e2c398bca7b6e/Cargo.lock && \
    mkdir src && echo 'fn main() {}' > src/main.rs && \
    cargo build --release --locked && \
    rm -rf /opt/rust-warmup

# Workspace
WORKDIR /workspace

CMD ["/bin/bash"]
