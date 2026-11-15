# atcoder-docker の作業メモ

## ブランチとコミット

- `claude.allowbase` は設定されていない。master へのコミットは git-guard に拒否される。
- git-guard が `agent/` と `worktree-` 以外のブランチ名を拒否するので、`git switch -c feat/...` は Claude からは作れない。`feat/...` を使うときは、ユーザーが `! git switch -c <名前>` で作る (2026-11-15)。

## 言語の選択 (build-arg `LANGS`)

- `Dockerfile` 先頭の `ARG LANGS=cpp,python,rust` で、イメージに入れる言語を選ぶ。ghcr の配布と CI は既定値 (全言語) のままで、言語ごとのタグは作らない (2026-11-15 にユーザーが決定)。
- 言語ごとの `RUN` は先頭に `case ",$LANGS," in *,<lang>,*) ;; *) exit 0 ;; esac &&` を付けて、対象外なら何もせず終わらせる。新しく言語固有の `RUN` を足すときも同じガードを付ける。
- `COPY --from=<stage>` は参照先のステージを必ずビルドさせる。そのため `cxx-libs-build` と `boost-build` は中の `RUN` をガードし、C++ を外したときは空の `/opt/cxx`・`/opt/boost` を残す。
- `docker buildx build --call=outline .` は、グローバルの `ARG` の直前にある「`# <引数名> <説明>`」の形のコメントだけを説明として表示する。`# LANGS: ...` のようにコロンを付けると拾われない (2026-11-15 に確認)。
- `LANGS` の値は light の最初の `RUN` で検査する。`cpp, python` のように空白が入ると `*,python,*` に当たらず、Python が黙って外れる。そのため英小文字とカンマ以外の文字を拒否している。
- `test/light.sh` は `python3.13`・`rustc` が無ければ、その言語の検査を飛ばす。`test/full.sh` は `/usr/local/share/ojt/cxx-flags` が無ければ C++ 外部ライブラリの検査を飛ばす。
- 確かめ方: この host (arm64、2 コア) で light を `LANGS=cpp` と `LANGS=python,rust` でビルドし、`docker run --rm` でテストを走らせる。テストのコンテナは残さない (ユーザーの指示)。既定値の full は host では重いので CI に任せる。
