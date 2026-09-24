# atcoder-docker

AtCoder の 2025-10 ジャッジと同じ処理系を入れた Docker イメージ。これ単体で、問題の取得から解答の作成、サンプルでの検査までを行える。提出はブラウザから行う (後述)。

- 対応: linux/amd64、linux/arm64
- 配布: `ghcr.io/carbon-nil/atcoder-docker`

## イメージ: light と full

| | light | full |
|---|---|---|
| 想定する用途 | アルゴリズム (ABC / ARC / AGC) | ヒューリスティック (AHC) の開発 |
| 中身 | 3 言語の処理系、ac-library、問題取得・検査のツール | light に加えて、AtCoder のジャッジが採用している外部ライブラリ (数値計算・最適化・機械学習・乱数など) |
| タグ | `4.1.0-light` / `latest-light` (`4.1.0` / `latest` も light) | `4.1.0-full` / `latest-full` |

アルゴリズムのコンテストは標準ライブラリと ac-library でほぼ足りるので、light で十分。AHC では乱数・数値計算・最適化などの外部ライブラリをジャッジと同じ条件で使いたいので、full を使う。

### 共通 (light / full)

| 言語 | 処理系 | ジャッジと合わせている点 |
|---|---|---|
| C++ | GCC 15.2.0 (`g++`) | `-std=gnu++23 -O2 -DATCODER -DONLINE_JUDGE` などのフラグ (`ojt` が付ける) |
| Python | CPython 3.13.7 (`python3.13`)、PyPy 3.11 v7.3.20 (`pypy3`) | `-X int_max_str_digits=0` |
| Rust | 1.89.0 (`rustc`, `cargo`) | `--cfg atcoder` (cargo の設定) |

- C++: [AtCoder Library (ac-library)](https://github.com/atcoder/ac-library) v1.6 (`#include <atcoder/all>`)
- ツール: [online-judge-tools](https://github.com/online-judge-tools/oj) (`oj`) 11.5.1、[atcoder-cli](https://github.com/Tatamo/atcoder-cli) (`acc`) 2.2.0、[aclogin](https://github.com/key-moon/aclogin)、自作のコマンド `ojt` / `vc` (後述)

### full のみ

**C++**

| ライブラリ | バージョン | 主な用途 |
|---|---|---|
| Boost | 1.83 | 多倍長整数、幾何、グラフなど |
| GMP | 6.3.0 | 多倍長演算 |
| Eigen | 3.4.0 | 行列・線形代数 |
| Abseil | 20250512.1 | ハッシュコンテナなど |
| Z3 | 4.8.12 | SMT ソルバ |
| immer / range-v3 (0.12.0) / unordered_dense | - | 永続データ構造、range、高速なハッシュマップ |
| LightGBM | 4.6.0 | 勾配ブースティング |
| LibTorch | 2.8.0 (CPU) | 機械学習 |
| OR-Tools | 9.14 | 最適化 (LP / MIP / CP-SAT) |

**Python (CPython 3.13)**

numpy、scipy、pandas、scikit-learn、networkx、PuLP、bitarray、more-itertools、mpmath、shapely、sortedcontainers、sympy、z3-solver、ac-library-python、acl-cpp-python、cppyy (3.5.0)

**Rust**

AtCoder と同じ `Cargo.toml` / `Cargo.lock` ([rust-lang-ja/atcoder-proposal@7a724cd](https://github.com/rust-lang-ja/atcoder-proposal/tree/7a724cdf84202ce3bef84527676e2c398bca7b6e)) の crate を事前にビルドしてある。`Cargo.toml` の `[dependencies]` に書けば、ネットワークなしで (`--offline`) 使える。主なもの: proconio、ac-library-rs、itertools、rand 系、num 系、petgraph、ndarray、nalgebra、superslice、rustc-hash、smallvec など。

## 使い方

### docker run

```sh
docker run --rm -it -v "$PWD":/workspace ghcr.io/carbon-nil/atcoder-docker:4.1.0-light
```

このリポジトリの `docker-compose.yml` は、手元でビルドしたイメージにカレントディレクトリを `/workspace` としてマウントする。

既定のユーザーは root なので、マウントしたディレクトリに作ったファイルはホストでは root の所有になる。避けたいときは、uid をホストのユーザーに合わせる次の devcontainer を使う。

### VS Code の Dev Containers

```json
{
  "image": "ghcr.io/carbon-nil/atcoder-docker:4.1.0-light",
  "workspaceMount": "source=${localWorkspaceFolder},target=/workspace,type=bind",
  "workspaceFolder": "/workspace",
  "remoteUser": "ubuntu"
}
```

`remoteUser` を `ubuntu` にすると、Linux の VS Code がこのユーザーの uid をホストのユーザーに合わせるので、作ったファイルはホストのユーザーの所有になる。すべての処理系とツールは `ubuntu` ユーザーでも使える。

利用例: [carbon-nil/atcoder-solutions](https://github.com/carbon-nil/atcoder-solutions) (非公開) は、このイメージに自作ライブラリ [atcoder-library](https://github.com/carbon-nil/atcoder-library) と提出用の展開スクリプトを組み合わせている。

## コマンド

| コマンド | 内容 |
|---|---|
| `ojt [pypy]` | カレントディレクトリの `main.cpp` / `main.py` / `main.rs` をジャッジと同じ条件でビルドし、`test/` のサンプルで検査する (`oj t`)。`pypy` を付けると Python を PyPy で動かす。`main.rs` は `Cargo.toml` があれば `cargo build --release`、なければ `rustc -O` |
| `vc <URL か ID> [-t テンプレート]` | [AtCoder Problems](https://kenkoooo.com/atcoder/) のバーチャルコンテストを、問題ごとに `vc/<ID の先頭 8 文字>/<a,b,...>/` に展開する。acc のテンプレートを置き、`oj d` でサンプルを `test/` に取得し、`vc/<ID>/README.md` に問題へのリンクをまとめる。既にある問題ディレクトリは上書きしない。サンプルの無い問題 (インタラクティブ問題など) は警告して続ける |
| `acc new <コンテスト ID>` | コンテストの問題ディレクトリとサンプルを作る (atcoder-cli)。テンプレートは `acc config-dir` に置く |
| `oj d <問題 URL>` / `oj t` | サンプルの取得 / 検査 (online-judge-tools) |
| `aclogin` | ブラウザの `REVEL_SESSION` cookie を貼って、acc と oj をログイン状態にする |

`ojt` と `vc` の本体は `bin/` にあり、イメージの `/usr/local/bin` に置かれる。

## 解答から提出までの流れ

```sh
aclogin                    # 初回と、コンテナを作り直したとき
acc new abc400             # または vc <バーチャルコンテストの URL>
cd abc400/a
# main.cpp を書く
ojt                        # サンプルで検査 (AC になるまで繰り返す)
```

検査が通ったら、`main.*` の中身をブラウザで AtCoder の提出欄に貼って提出する。言語は処理系に合わせて選ぶ (`C++23 (GCC 15.2.0)`、`Python (CPython 3.13.7)` / `Python (PyPy 3.11-v7.3.20)`、`Rust (rustc 1.89.0)`)。

AtCoder は Cloudflare Turnstile を導入しているため、`acc submit` / `oj submit` などコマンドラインからの提出と、`acc login` / `oj login` は通らない。ログインは `aclogin` で cookie を渡し、提出はブラウザで行う。サンプルの取得 (`oj d`) は、公開中の問題ならログインなしでもできる。

## ビルドと公開

- `v*` のタグを push すると、GitHub Actions が light / full を amd64 と arm64 のネイティブ runner でビルドし、ghcr.io に公開する。ビルドキャッシュは `ghcr.io/carbon-nil/atcoder-docker-cache` に置く
- Actions の手動実行 (`workflow_dispatch`) はビルドの確認だけで、公開はしない
- full の cppyy は arm64 向けの wheel が PyPI にないので、`cppyy-wheel.yml` でビルドして Release (`cppyy-cling-6.32.8`) に置いたものを使う
- 手元でビルドする場合: `docker buildx build --target light -t atcoder-docker:light .` (full は `--target full`)

## ライセンス

このリポジトリ (Dockerfile、`bin/` のスクリプト、ワークフロー) は [MIT License](LICENSE)。

イメージに含まれるソフトウェアは、それぞれのライセンスに従う。主なもの:

| ソフトウェア | ライセンス |
|---|---|
| GCC | GPL-3.0 (GCC Runtime Library Exception 付き) |
| CPython / PyPy / Rust | PSF-2.0 / MIT / MIT または Apache-2.0 |
| AtCoder Library (ac-library) | CC0-1.0 |
| online-judge-tools / atcoder-cli / aclogin | MIT / BSD-3-Clause / MIT |
| Boost / immer / range-v3 | BSL-1.0 |
| GMP / Eigen | LGPL-3.0 または GPL-2.0 / MPL-2.0 |
| Abseil / OR-Tools | Apache-2.0 |
| Z3 / LightGBM / unordered_dense | MIT |
| LibTorch | BSD-3-Clause |
| Python・Rust のライブラリ | 各パッケージのライセンス (numpy・scipy・pandas・scikit-learn などは BSD-3-Clause、ac-library-python・acl-cpp-python は CC0-1.0) |
