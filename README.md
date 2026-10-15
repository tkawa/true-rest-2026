# true-rest-2026

Kaigi on Rails 2026 の発表「真のREST 2026」で示した比較実験の、装置と実行記録の一式です。
同じ業務ロジックの上に HTML（Hotwire）と JSON API の二つの表現を並べた ToDo アプリに、同じ LLM エージェントへ同じ自然言語の指示を与え、表現の違いだけで挙動がどう変わるかを測りました。

スライド: https://tkawa.github.io/true-rest-2026/ja/

## 構成

| 場所 | 中身 |
|---|---|
| [`todo_app/`](todo_app/) | 実験対象の Rails アプリ。`/` に HTML、`/api` に JSON を同じコントローラでマウントしている |
| [`agent/`](agent/) | 計測の装置。LLM を呼ぶ薄いループ、汎用 HTTP ツール、ランナー、DB 差分による判定、集計。Claude Code を同じ条件で走らせる参考実行も含む。経緯は [`agent/NOTES.md`](agent/NOTES.md) |
| `runs*/` | 実行記録（データセット）。下の表 |
| [`runs-probes/`](runs-probes/) | 探りの記録。どの集計にも入っていない |
| [`docs/`](docs/) | 実装と実行を Claude Code に委ねるために書いた設計書と、元のリポジトリとのコミットの対応表 |

## データセット

| ディレクトリ | 実行数 | モデル | 実行日（UTC） | 目的 |
|---|---|---|---|---|
| [`runs/`](runs/README.md) | 136 | `claude-sonnet-5` | 2026-09-19 | 本番。s0〜s4 の自作ループ 110 件と、s2 の参考実行（Claude Code）26 件 |
| [`runs-pilot/`](runs-pilot/README.md) | 44 | `claude-sonnet-5` | 2026-09-19 | 予備実行。条件を固定する前のもの。本番の集計に入らない |
| [`runs-claude-fable-5-1/`](runs-claude-fable-5-1/README.md) | 136 | `claude-fable-5-1` | 2026-09-27 | 本番と同じ装置で、モデルだけを変えた追試 |
| [`runs-claude-sonnet-5-cli-2.1.283/`](runs-claude-sonnet-5-cli-2.1.283/README.md) | 10 | `claude-sonnet-5` | 2026-09-27 | 参考実行の差がモデルによるか CLI の版によるかの切り分け |
| [`runs-ablation-claude-sonnet-5/`](runs-ablation-claude-sonnet-5/README.md) | 98 | `claude-sonnet-5` | 2026-10-09 | 切除実験（s4 の仕様書の文言、s5 の文字数制限、s6 の移動）。api_error で除外した 8 件を含む |
| [`runs-due-claude-sonnet-5/`](runs-due-claude-sonnet-5/README.md) | 60 | `claude-sonnet-5` | 2026-10-10 | 期限と「今日」（s7、s8） |
| [`runs-attached-claude-sonnet-5/`](runs-attached-claude-sonnet-5/README.md) | 60 | `claude-sonnet-5` | 2026-10-10 | 付随する状態（コメントとサブタスク。s9、s10） |

実行数は `run.json` の数です。
発表の図の数字は `runs/` から出ています。
ほかのデータセットは追試と追加の実験で、`runs/` の数字を差し替えるものではありません。

各実行のディレクトリには、`run.json`（計測値と判定）、`transcript.jsonl`（API 呼び出しごとの送信と応答）、`requests.jsonl`（サーバ側のリクエスト記録）、`db.sqlite3`（実行後の DB）、`server.log`、`initial_message.md` があります。
形式の説明は [`runs/README.md`](runs/README.md) にあります。

## 結果の要約

数字は各データセットの `report.md`（`runs-due-claude-sonnet-5/` と `runs-attached-claude-sonnet-5/` は README）からとっています。
解釈はスライドと各データセットの README に任せ、ここでは判定の内訳だけを示します。

本番（`runs/`、各 N=10）の自作ループは、11 セルのうち 10 セルが success 10 でした。
残る 1 セルは s4 の `json`（アーカイブの操作を持たない古い仕様書）で、honest_failure 10 です。
アーカイブを載せた仕様書（`json_v2`）では success 10 でした。
参考実行（Claude Code、s2）は、HTML で前提の一行なしが success 3/10、ありが 8/10、JSON はどちらも 3/3 でした。

追試（`runs-claude-fable-5-1/`）では、s0 と s2 の HTML が 10/10 とも最初の API 呼び出しで `stop_reason: refusal` になりました。
そのほかの自作ループのセルは本番と同じ内訳で、s3 の HTML だけが success 9、refusal 1 です。
参考実行は 26/26 で success でした。
CLI だけを上げた切り分け（`runs-claude-sonnet-5-cli-2.1.283/`）は、s2 の HTML で success 4/10 でした。

切除実験（`runs-ablation-claude-sonnet-5/`）は、s4 の三つの JSON 条件がすべて honest_failure 10、s5 は `html` が success 10、`json` が success 9 と collateral 1、s6 は `html` が success 4 と collateral 6、三つの JSON 条件がすべて collateral 10 でした。

期限（`runs-due-claude-sonnet-5/`）は、`html` と `json_situated`（JSON に `today` を足した条件）が s7、s8 とも success 10 でした。
仕様書だけの `json` は、s7 が success 2、honest_failure 7、false_success 1、s8 が success 4、honest_failure 6 です。

付随する状態（`runs-attached-claude-sonnet-5/`）は、s9 の `html` が success 9 と honest_failure 1、`json` が collateral 10、`json_links`（件数とリンクを足した条件）が success 1、honest_failure 1、collateral 8 でした。
s10 は、親の ToDo を完了にした実行がどの条件でも 0 件です。
success と honest_failure の線引きが最終行の形式に左右されている点は、README の「判定規則の副作用」を見てください。

## 再現

手順の詳細は [`agent/README.md`](agent/README.md) と [`todo_app/README.md`](todo_app/README.md) にあります。
Ruby 4.0.7 と SQLite が必要です。
LLM を呼ぶ実行には `ANTHROPIC_API_KEY` が、参考実行には `claude` コマンドが要ります。

記録の再集計と再判定は、API キーなしでできます。

```sh
cd todo_app && bundle install && cd ..
cd agent && bundle install
bin/report                                    # runs/ から report.md を作り直す
RUNS_DIR=../runs-claude-fable-5-1 bin/report --against ../runs
bin/oracle --run ../runs/s2/json/<run_id>     # 1 実行の判定をやり直す
bundle exec rake test                         # LLM を呼ばない自己テスト
```

`bin/report` はコミット済みの `report.md` を上書きします。比べるときは、データセットを一時ディレクトリに写して `RUNS_DIR` で指してください。

新しく実行するときは、試し打ちを `RUNS_DIR=../runs-scratch` に向けます（`.gitignore` で除外してあります）。

```sh
cd agent
cp .env.example .env    # ANTHROPIC_API_KEY を書く
RUNS_DIR=../runs-scratch bin/run --scenario s2 --condition json --runs 1
```

## 方針

取った実行は、選ばずにすべて入れています。
API のタイムアウトで応答を得られなかった実行（api_error）も、集計からは除きますが記録は残しています。
`bin/agent` の任意の実行を除き、探りの実行もすべて `runs-probes/` に入れています。撮り直しと最初の試行の関係は `runs-probes/README.md` にあります。

参考実行（Claude Code）の記録には実行した人の環境が含まれるため、記録時と後処理の二段で匿名化しています。
記録時の処理は `agent/lib/agent/reference/sanitizer.rb`、後から取った記録への処理は `agent/script/sanitize-reference-records` です。
規則は [`runs/README.md`](runs/README.md) の「匿名化」にあります。

このリポジトリは、発表の準備に使った非公開のリポジトリから `experiment/` 以下を切り出したものです。
切り出すときに、次の二つの処理を全履歴にかけています。

- `todo_app/config/master.key` と `todo_app/config/credentials.yml.enc` を外した。実験は credentials を使っていない
- 9 月 20 日より前の参考実行の記録に残っていた `ls -la` の所有者欄（OS の利用者名に空白と `staff` が続く箇所）を `<USER>` に置き換えた

APIキーは記録のどこにも含まれません。

## 元のリポジトリとの対応

`run.json` の `harness_git_commit` と `todo_app_git_commit` は、切り出す前のリポジトリのハッシュです。
[`docs/commit-map.tsv`](docs/commit-map.tsv) で、このリポジトリのハッシュに引けます。
列は「元のハッシュ」「このリポジトリのハッシュ」「件名」です。

```sh
grep '^cd95754' docs/commit-map.tsv     # runs/ の実行で使ったコミット
```

`runs-ablation-claude-sonnet-5/` の `75386be` は、この表にありません。
スライドだけを変えたコミットで、切り出しで消えたためです。
このコミットの `experiment/` の中身は `d6fde2e`（元の `8684a92`）と同じです。
切除実験の実装（s5、s6 の追加など）は、実行の時点ではコミット前の作業ツリーにあり、後で（このリポジトリの `a84fde0`）コミットしました。
期限と付随する状態のデータセットにも同じ事情があり、各 README に注記があります。

タグ `experiment-2026-09-20` は、本番と予備実行の記録（`runs/`、`runs-pilot/`）を揃えた時点のコミットを指しています。

## ライセンス

| 対象 | ライセンス |
|---|---|
| コード（`agent/`、`todo_app/`）と設計書（`docs/`） | MIT（[`LICENSE`](LICENSE)） |
| 実行記録（`runs*/` と `runs-probes/` の下のすべて。各データセットの `README.md` と `report.md` を含む） | CC BY 4.0（[`LICENSE-DATA`](LICENSE-DATA)） |

実行記録を使うときは、出典としてこの発表とリポジトリを示してください。
