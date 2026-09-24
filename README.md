# atcoder-docker

問題の入出力例の取得、実装環境の構築、ビルドと実行の自動化を行う Docker イメージです。  
処理系とコンパイルオプションは AtCoder の 2025-10 ジャッジ (GCC 15.2.0 / CPython 3.13.7 / PyPy 3.11 / Rust 1.89.0) に合わせています。linux/amd64 と linux/arm64 に対応しています。

## 導入方法 / Installation

1. Docker をインストールする
2. ghcr.io から atcoder-docker を pull する

```bash
# latest-light: Algorithm Contest 用
docker pull ghcr.io/carbon-nil/atcoder-docker:latest-light
# latest-full: Heuristic Contest 用
docker pull ghcr.io/carbon-nil/atcoder-docker:latest-full
```

3. Docker コンテナを起動する  
full を使うときはタグを `latest-full` にします。VS Code の Dev Containers で使う場合は、`"remoteUser": "ubuntu"` を指定すると、作ったファイルがホストのユーザーの所有になります (root のままだとホストでは root の所有になります)。

```bash
docker run -it --rm -v "$(pwd)":/workspace ghcr.io/carbon-nil/atcoder-docker:latest-light
```

4. AtCoder にログインする  
AtCoder は Cloudflare Turnstile を導入しているため、`acc login` / `oj login` ではログインできません。  
Note: コンテナを作り直すたびに、`aclogin` でログインし直す必要があります。

```bash
# ブラウザで AtCoder にログインし、cookie の REVEL_SESSION の値を貼り付ける
aclogin
```

## 使い方 / Usage

### 問題の入出力例の取得 / Fetching Problem Samples

```bash
# コンテスト: abc123/a, abc123/b, ... にテンプレートと入出力例 (test/) を置く
acc new abc123
acc new abc123 --template python # テンプレートを指定する場合

# AtCoder Problems のバーチャルコンテスト: vc/<ID の先頭 8 文字>/a, b, ... に置く
vc https://kenkoooo.com/atcoder/#/contest/show/<ID>
vc <ID> -t rust

# 1 問だけ: カレントディレクトリの test/ に置く
oj d https://atcoder.jp/contests/abc123/tasks/abc123_a
```

`vc` はコンテストの問題へのリンクを `vc/<ID>/README.md` にまとめます。既にある問題ディレクトリは上書きせず、入出力例の無い問題 (インタラクティブ問題など) は警告を出して続行します。

### ビルドと実行 / Build and Run

問題のディレクトリ (`main.*` と `test/` がある場所) で `ojt` を実行すると、ジャッジと同じ条件でビルドし、入出力例で検査します (`oj t`)。

```bash
# C++ の場合
ojt

# Python の場合
ojt # Python 3.13
ojt pypy # PyPy 3.11

# Rust の場合
# Cargo.toml があれば cargo build --release、なければ rustc -O main.rs
ojt
```

`ojt` の後ろに付けた引数は `oj t` に渡されます (例: `ojt -e 1e-6` で誤差を許容)。

### 提出 / Submission

Cloudflare Turnstile のため、`acc submit` / `oj submit` による提出はできません。

そのため、問題なく実装できたら、`main.*` の中身をブラウザで AtCoder の提出欄に貼り付けて提出します。言語は `C++23 (GCC 15.2.0)`、`Python (CPython 3.13.7)` / `Python (PyPy 3.11-v7.3.20)`、`Rust (rustc 1.89.0)` を選びます。

### テンプレートの設定 / Setting Up Templates

`acc new` と `vc` は、acc の設定ディレクトリにあるテンプレートを問題ごとにコピーします。

```bash
# テンプレートの置き場所
acc config-dir

# 例: C++ のテンプレートを作る
mkdir -p "$(acc config-dir)/cpp"
cat > "$(acc config-dir)/cpp/main.cpp" <<'EOF'
#include <bits/stdc++.h>
using namespace std;

int main() {
}
EOF
cat > "$(acc config-dir)/cpp/template.json" <<'EOF'
{"task": {"program": ["main.cpp"], "submit": "main.cpp"}}
EOF

# 既定のテンプレートにする
acc config default-template cpp
```

Rust で `Cargo.toml` を置く場合は、`template.json` の `cmd` でパッケージ名と bin 名を問題のディレクトリ名に書き換えます (`ojt` は `./target/release/<ディレクトリ名>` を実行するため)。

```json
{"task": {"program": ["main.rs", "Cargo.toml"], "submit": "main.rs",
          "cmd": "sed -i \"s/__TASK__/$(basename \"$PWD\")/\" Cargo.toml"}}
```

## その他 / Others

### ライブラリ / Libraries

**light / full 共通**

- C++: [AtCoder Library (ac-library)](https://github.com/atcoder/ac-library) v1.6
- ツール: [online-judge-tools](https://github.com/online-judge-tools/oj) (`oj`)、[atcoder-cli](https://github.com/Tatamo/atcoder-cli) (`acc`)、[aclogin](https://github.com/key-moon/aclogin)、`ojt`、`vc`

**full のみ (Heuristic Contest 用)**

AtCoder のジャッジが採用している外部ライブラリを入れています。

| 言語 | ライブラリ |
|---|---|
| C++ | Boost 1.83、GMP 6.3.0、Eigen 3.4.0、Abseil 20250512.1、Z3 4.8.12、immer、range-v3 0.12.0、unordered_dense、LightGBM 4.6.0、LibTorch 2.8.0 (CPU)、OR-Tools 9.14 |
| Python (CPython) | numpy、scipy、pandas、scikit-learn、networkx、PuLP、bitarray、more-itertools、mpmath、shapely、sortedcontainers、sympy、z3-solver、ac-library-python、acl-cpp-python、cppyy |
| Rust | AtCoder と同じ `Cargo.toml` / `Cargo.lock` ([rust-lang-ja/atcoder-proposal](https://github.com/rust-lang-ja/atcoder-proposal/tree/7a724cdf84202ce3bef84527676e2c398bca7b6e)) の crate 一式 (proconio、ac-library-rs、itertools、rand、num、petgraph、ndarray、nalgebra など)。事前にビルドしてあるので、`Cargo.toml` の `[dependencies]` に書けばネットワークなしで使えます |

### ライセンス / License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

イメージに含まれるソフトウェアは、それぞれのライセンスに従います。
- GCC: GPL-3.0 with GCC Runtime Library Exception
- ac-library: CC0-1.0
- online-judge-tools: MIT
- atcoder-cli: BSD-3-Clause
- etc.

### 各種リンク / Links

Discord: @carbon_nil  
X (Twitter): @carbon_nil
