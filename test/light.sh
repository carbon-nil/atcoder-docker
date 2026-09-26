#!/bin/bash
# C++23、Python、PyPy、Rust 2024 の単一ファイルを ojt でビルド・実行できるかを確かめる
set -eu

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

for language in cpp python rust; do
    mkdir -p "$tmp/$language/test"
    touch "$tmp/$language/test/sample-1.in"
    echo 3 > "$tmp/$language/test/sample-1.out"
done

cat > "$tmp/cpp/main.cpp" <<'EOF'
#include <bits/stdc++.h>
int main() {
    std::println("{}", 1 + 2);
}
EOF
cat > "$tmp/python/main.py" <<'EOF'
print(1 + 2)
EOF
cat > "$tmp/rust/main.rs" <<'EOF'
fn main() {
    if let Some(x) = Some(1) && x > 0 {
        println!("{}", x + 2);
    }
}
EOF

cd "$tmp/cpp"
ojt
cd "$tmp/python"
ojt
ojt pypy
cd "$tmp/rust"
ojt

python3 /test/bundle.py
