#!/bin/bash
# light の各言語と、full の C++ 外部ライブラリを ojt でビルド・実行できるかを確かめる
set -eu

bash "$(dirname "$0")/light.sh"

# C++ の外部ライブラリは LANGS で cpp を外すと入らない
[ -f /usr/local/share/ojt/cxx-flags ] || exit 0

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp "$(dirname "$0")/full-smoke.cpp" "$tmp/main.cpp"
mkdir -p "$tmp/test"
touch "$tmp/test/sample-1.in"
echo '2 1180591620717411303424 15 10 4 2 1 4 3' > "$tmp/test/sample-1.out"
cd "$tmp"
ojt
