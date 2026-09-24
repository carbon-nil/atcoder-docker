FROM ubuntu:24.04 AS base-toolchain

ENV TZ=Asia/Tokyo \
    DEBIAN_FRONTEND=noninteractive

RUN apt update && \
    apt install -y --no-install-recommends time wget unzip git curl ca-certificates cmake && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

FROM base-toolchain AS gcc

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
ENV CXX=g++ CC=gcc

# Light version
FROM gcc AS light

ARG TARGETARCH

# C++
RUN git clone --depth 1 -b v1.6 https://github.com/atcoder/ac-library.git /lib/ac-library
ENV CPLUS_INCLUDE_PATH="/usr/local/include:/lib/ac-library"

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
# root 以外のユーザー (devcontainer の remoteUser) も使えるよう、公式の rust イメージと同じく /usr/local に置く
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH="/usr/local/cargo/bin:${PATH}"
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --no-modify-path --default-toolchain 1.89.0 --profile minimal && \
    rustup component add rust-src && \
    rm -rf "$RUSTUP_HOME"/toolchains/*/share/doc "$CARGO_HOME"/registry/cache && \
    chmod -R a+w "$RUSTUP_HOME" "$CARGO_HOME"
COPY <<'EOF' /usr/local/cargo/config.toml
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
# acc の設定はユーザーごとなので、devcontainer の remoteUser (ubuntu) にも入れる
RUN npm install -g atcoder-cli && \
    npm cache clean --force && \
    acc config default-test-dirname-format test && \
    runuser -u ubuntu -- acc config default-test-dirname-format test

# Command
COPY --chmod=755 bin/ojt /usr/local/bin/ojt

# AtCoder Problems のバーチャルコンテストを acc new と同じ形 (テンプレート + test/) で vc/<ID>/<a,b,...>/ に展開する
COPY --chmod=755 bin/vc /usr/local/bin/vc

# cppyy-cling wheel (linux/arm64 用。.github/workflows/cppyy-wheel.yml が Release に置く)
# pip の隔離ビルドは最新の cmake (4 系) を入れて設定に失敗するので、隔離せずにシステムの cmake (3.28) を使う
# 同梱の LLVM は GCC 14.3 以降だと C++20 でコンパイルできない (root-project/root#18939) ので、g++-13 でビルドする
FROM light AS cppyy-cling-build
RUN python3.13 -m pip install --no-cache-dir --break-system-packages setuptools wheel && \
    CC=gcc-13 CXX=g++-13 python3.13 -m pip wheel --no-cache-dir --no-deps --no-build-isolation \
        cppyy-cling==6.32.8 -w /wheels

FROM scratch AS cppyy-cling-wheel
COPY --from=cppyy-cling-build /wheels /

# arm64 の配布済み OR-Tools は AlmaLinux ビルドで libstdc++ のシンボルを再公開し、LibTorch と併用すると落ちる。
# AtCoder と同じくソースからビルドし、full の残りとは独立してキャッシュできるよう別ステージにする。
FROM gcc AS cxx-libs-build
WORKDIR /tmp/cxx

# OR-Tools (PDLP など) は Eigen3 の CMake ターゲットを使う。AtCoder と同じく apt の Eigen を入れておく
RUN apt update && \
    apt install -y --no-install-recommends libeigen3-dev && \
    apt clean && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 -b 20250512.1 https://github.com/abseil/abseil-cpp.git && \
    cd abseil-cpp && \
    cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_STANDARD=20 \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DABSL_ENABLE_INSTALL=ON \
        -DABSL_PROPAGATE_CXX_STD=ON -DCMAKE_INSTALL_PREFIX=/opt/cxx && \
    cmake --build build -j"$(nproc)" --target install && \
    cd /tmp/cxx && rm -rf /tmp/cxx/*
RUN wget -O or-tools.tar.gz https://github.com/google/or-tools/archive/refs/tags/v9.14.tar.gz && \
    mkdir or-tools && tar -xf or-tools.tar.gz -C or-tools --strip-components=1 && \
    cd or-tools && \
    cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_CXX=ON \
        -DBUILD_BZip2=ON -DBUILD_ZLIB=ON -DBUILD_Protobuf=ON -DBUILD_re2=ON \
        -DUSE_COINOR=ON -DBUILD_CoinUtils=ON -DBUILD_Osi=ON -DBUILD_Clp=ON \
        -DBUILD_Cgl=ON -DBUILD_Cbc=ON -DUSE_GLPK=ON -DBUILD_GLPK=ON \
        -DUSE_HIGHS=ON -DBUILD_HIGHS=ON -DUSE_SCIP=ON -DBUILD_SCIP=ON \
        -DBUILD_soplex=ON -DBUILD_Boost=ON -DBUILD_SAMPLES=OFF \
        -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_PREFIX_PATH=/opt/cxx -DCMAKE_INSTALL_PREFIX=/opt/cxx && \
    cmake --build build -j"$(nproc)" --target install && \
    cd /tmp/cxx && rm -rf /tmp/cxx/*
# 依存ライブラリが man を prefix/man に入れるが、Ubuntu の /usr/local/man は symlink なので full にコピーできない。man は使わないので消す
RUN rm -rf /opt/cxx/man

# AtCoder は Boost 1.88.0 をソースからビルドする。Ubuntu の 1.83 には charconv、contract、process、stacktrace_from_exception がない。
# 独立してキャッシュできるよう別ステージにする。
FROM gcc AS boost-build
WORKDIR /tmp/boost
RUN wget -q -O boost.tar.gz https://archives.boost.io/release/1.88.0/source/boost_1_88_0.tar.gz && \
    mkdir src && tar -xzf boost.tar.gz -C src --strip-components=1 && \
    cd src && \
    ./bootstrap.sh --with-toolset=gcc --without-libraries=mpi,graph_parallel,python --prefix=/opt/boost && \
    ./b2 toolset=gcc link=static threading=single variant=release cflags=-w cxxflags=-std=gnu++23 -j"$(nproc)" -d0 install && \
    cd / && rm -rf /tmp/boost

# Full version
FROM light AS full
ARG TARGETARCH
WORKDIR /opt

# C++ Library
RUN apt update && \
    apt install -y --no-install-recommends \
        libeigen3-dev \
        libgmp-dev && \
    apt clean && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 -b v0.8.1 https://github.com/arximboldi/immer.git && \
    cp -r immer/immer /usr/local/include/ && \
    git clone --depth 1 -b 0.12.0 https://github.com/ericniebler/range-v3.git && \
    cp -r range-v3/include/* /usr/local/include/ && \
    git clone --depth 1 -b v4.5.0 https://github.com/martinus/unordered_dense.git && \
    cp unordered_dense/include/ankerl/unordered_dense.h /usr/local/include/
# AtCoder は Z3 4.15.2 を使う。ビルドせず公式リリースのバイナリを入れる
RUN case "$TARGETARCH" in \
        amd64) z3_arch=x64-glibc-2.39 ;; \
        arm64) z3_arch=arm64-glibc-2.34 ;; \
        *) echo "Unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac && \
    wget -O z3.zip "https://github.com/Z3Prover/z3/releases/download/z3-4.15.2/z3-4.15.2-${z3_arch}.zip" && \
    unzip -q z3.zip && \
    cp z3-4.15.2-${z3_arch}/include/* /usr/local/include/ && \
    cp z3-4.15.2-${z3_arch}/bin/libz3.so* /usr/local/lib/ && \
    ldconfig && \
    rm -rf z3.zip z3-4.15.2-${z3_arch}
# 別ステージでビルドした Abseil と OR-Tools を依存ライブラリごと入れる
COPY --from=cxx-libs-build /opt/cxx/ /usr/local/
# 別ステージでビルドした Boost 1.88.0 を入れる (OR-Tools が同梱の Boost を入れていても上書きするよう、その後に置く)
COPY --from=boost-build /opt/boost/ /usr/local/
# リリースの tarball は submodule (eigen など) を同梱しているので、GitLab から取らずに済む
# tarball の Python パッケージ lightgbm/ が CLI の出力先と衝突するので、AtCoder と同じくライブラリだけをビルドする。
# AtCoder と同じく静的ライブラリにして /usr/local に入れる (#include <LightGBM/c_api.h> と -l_lightgbm で使う)
RUN wget -O lightgbm.tar.gz https://github.com/microsoft/LightGBM/releases/download/v4.6.0/lightgbm-4.6.0.tar.gz && \
    mkdir LightGBM && tar -xf lightgbm.tar.gz -C LightGBM --strip-components=1 && rm lightgbm.tar.gz && \
    cd LightGBM && mkdir build && cd build && \
    cmake -DBUILD_CLI=OFF -DBUILD_STATIC_LIB=ON -DCMAKE_INSTALL_PREFIX=/usr/local .. && make -j$(nproc) install && \
    cd /opt && rm -rf LightGBM
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
    rm libtorch.zip && \
    # amd64 の libtorch は古い protobuf の静的ライブラリを同梱していて、-lprotobuf が OR-Tools の protobuf ではなくこちらを拾う。
    # AtCoder と同じく消す
    rm -f /opt/libtorch/lib/libprotobuf.a /opt/libtorch/lib/libprotobuf-lite.a /opt/libtorch/lib/libprotoc.a
ENV CPLUS_INCLUDE_PATH="/usr/local/include:/lib/ac-library:/usr/include/eigen3:/opt/libtorch/include:/opt/libtorch/include/torch/csrc/api/include" \
    LD_LIBRARY_PATH="/usr/local/lib:/opt/libtorch/lib"
# ojt が外部ライブラリを AtCoder と同じ define とリンクのフラグでビルドするためのファイル。イメージに無いライブラリの -l は落とす
COPY cxx/full-flags.txt /tmp/cxx/
RUN mkdir -p /usr/local/share/ojt && \
    while read -r f; do \
        case "$f" in -l*) \
            echo 'int main() {}' | g++ -x c++ - -o /dev/null -L/opt/libtorch/lib "$f" 2> /dev/null || \
                { echo "ojt: skip $f (not installed)"; continue; } ;; \
        esac; \
        echo "$f" >> /usr/local/share/ojt/cxx-flags; \
    done < /tmp/cxx/full-flags.txt && \
    rm -rf /tmp/cxx

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
# cppyy は AtCoder と同じ組み合わせに固定する。PyPI に arm64 の cppyy-cling wheel はないので、
# cppyy-cling-wheel ステージで作って Release に置いたもの (.github/workflows/cppyy-wheel.yml) を使う。
# 見つからなければ cppyy-cling-build ステージと同じ条件でソースからビルドする (40 分ほどかかる)
RUN python3.13 -m pip install --no-cache-dir --break-system-packages setuptools wheel && \
    for p in cppyy-cling==6.32.8 cppyy-backend==1.15.3 cppyy==3.5.0; do \
        CC=gcc-13 CXX=g++-13 python3.13 -m pip install --no-cache-dir --break-system-packages --no-build-isolation \
            --prefer-binary --find-links https://github.com/carbon-nil/atcoder-docker/releases/expanded_assets/cppyy-cling-6.32.8 \
            "$p" || exit 1; \
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
    rm -rf /opt/rust-warmup && \
    chmod -R a+w "$CARGO_HOME"

# Workspace
WORKDIR /workspace

CMD ["/bin/bash"]
