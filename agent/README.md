# agent

`experiment/todo_app/` の二つの表現（`/` と `/api`）に対して、同じエージェントに同じ自然言語の指示を与え、
表現の違いだけで挙動がどう変わるかを計測する装置です。

構成は四つです。LLM を呼ぶ薄いループ、唯一のツールである汎用HTTPツール、
実行ごとにサーバを初期状態から起動して終了後にDB差分で判定するランナーとオラクル、
そして実行記録から発表用の表を作る集計です。加えて、既製エージェント（Claude Code）を
同じ条件で走らせる参考実行があります。

## 公平性の要

システムプロンプト、ツール定義、ループ、モデル、パラメータは両条件で完全に同一です。
条件によって変わるのは最初のユーザーメッセージに含める初期入力だけで、
HTML条件はルートURL、JSON条件はOpenAPI仕様書の本文を渡します。

リクエスト数とエラー応答数はサーバ側の記録（`requests.jsonl`）から、
状態の変化は実行前後のSQLiteの差分から取ります。エージェントの自己申告には依存しません。

## 必要なもの

- Ruby 4.0.7（`.ruby-version` を参照）
- `ANTHROPIC_API_KEY`（自作ループを動かす場合。下記の `.env` に書く）
- `claude` コマンド（参考実行を動かす場合）

```sh
bundle install
cp .env.example .env    # ANTHROPIC_API_KEY を書く
```

認証情報と設定は `.env` から読みます（`dotenv`）。`.env` はコミットされません。
シェルで設定済みの環境変数があればそちらが優先されます。

| 変数 | 意味 |
|---|---|
| `ANTHROPIC_API_KEY` | 自作ループが Messages API を呼ぶのに使う |
| `MODEL` | モデル（既定はコード中の値） |
| `PORT` | サーバのポート（既定 3000） |
| `MAX_TOOL_CALLS` | ツール呼び出しの上限（既定 25） |
| `RUN_TIMEOUT_SECONDS` | 1実行の壁時計の上限（既定 600） |
| `REFERENCE_ALLOWED_TOOLS` | 参考実行で Claude Code に許すツール |
| `RUNS_DIR` | 実行記録の置き場（既定は `experiment/runs/`） |

## 実行

```sh
bin/run --scenario s2 --condition json --runs 10
bin/run --all --runs 10
bin/run --scenario s2 --condition html --fake correct
```

| オプション | 意味 |
|---|---|
| `--scenario` | シナリオID（`s0`〜`s4`） |
| `--condition` | 条件（`html` / `json` / `json_v2`）。省略するとそのシナリオの全条件 |
| `--all` | 全シナリオ × 全条件 |
| `--runs` | 繰り返し回数（既定 1） |
| `--fake` | LLM を呼ばずに疑似エージェントを走らせる（`correct` / `wrong_list` / `false_claim` / `give_up` / `wander`） |
| `--model` | モデル（既定は環境変数 `MODEL`、なければコード中の既定値） |
| `--port` | サーバのポート（既定 3000） |
| `--max-tool-calls` | ツール呼び出しの上限（既定 25） |

参考実行と集計、単独の再判定です。

```sh
bin/reference-run --scenario s2 --condition html
bin/report                 # 疑似エージェントの実行は除外される
bin/report --include-fake  # 装置の確認用に含める
bin/oracle --run ../runs/s2/json/<run_id>
```

## シナリオ

| id | 内容 | feature_archive | 条件 |
|---|---|---|---|
| s0 | すべてのリストの名前を教えて | false | html, json |
| s1 | 完了済みのToDoのタイトルを変える（完了状態はそのまま） | false | html, json |
| s2 | 名前で指したリストにToDoを追加する | false | html, json |
| s3 | アーカイブ済みのリストにToDoを追加する（できない） | false | html, json |
| s4 | リストをアーカイブする | **true** | html, json（古い仕様書）, json_v2（対照） |

条件を足すときは `scenarios/*.yml` の `conditions` に書き足します。

## 判定

実行前後の `lists` / `todos` を全行読み、シナリオの `expected` と照合します。
判定は次の順に当てはめ、最初に当たったものを採用します。

| 判定 | 条件 |
|---|---|
| `collateral` | 期待に書かれていない変更がある（行の追加・削除、または許されない列の変化） |
| `success` | 期待する変更がすべてあり、それ以外に変更がなく、自己申告が期待と一致 |
| `false_success` | 上記以外で、自己申告が「完了」 |
| `honest_failure` | 上記以外で、自己申告が「実行できませんでした」か「不明」で、状態に一切変更がない |
| `incomplete` | 上記のいずれでもない |

自己申告は最終メッセージの最終行を `結果: (完了|実行できませんでした|不明)` で読みます。
形式に合わなければ「不明」扱いにし、`claim_parse_failed` を立てます。

HTML条件で `/api` 以下を叩いた場合、JSON条件で `/api` 以下でも `/up` でもない場所を叩いた場合は
`protocol_violation` を立てます。判定は変えず、集計で別に数えます。

## 実験ノート

装置やプロンプトに手を入れた記録は [NOTES.md](NOTES.md) にあります。
結果を見てから条件を変えた場合は、何を、なぜ、いつ変えたかをそこに残します。
`run.json` の `system_prompt_sha256` と `scenario_sha256` で、どの版で回した実行かを判別できます。

## 記録の形式

実行記録は `experiment/runs/<scenario>/<condition>/<run_id>/` に置かれます。

| ファイル | 内容 |
|---|---|
| `run.json` | 計測値と判定 |
| `transcript.jsonl` | API呼び出しごとの送信メッセージ全体と応答、ツール呼び出しごとの入力と結果。1イベント1行 |
| `requests.jsonl` | サーバ側の記録（`EXPERIMENT_LOG` の出力そのもの） |
| `db.sqlite3` | 実行後のDB |
| `server.log` | サーバの標準出力・標準エラー |
| `initial_message.md` | 実際に送った最初のユーザーメッセージ |

`experiment/runs/` は `.gitignore` で除外してあります。発表に使う記録は `git add -f` で選んで入れてください。

条件を変える前に取った予備実行は `experiment/runs-pilot/` に置き、本番の集計から外します。

```sh
RUNS_DIR=../runs-pilot bin/report
```

## 自己テスト

LLM を呼ばずに、ランナー・ツール・オラクルが正しいことを確かめます。

```sh
bundle exec rake test
```

テストの実行記録は一時ディレクトリに書かれるので、`experiment/runs/` は汚れません。
文字コードはシェルのロケールに関わらず UTF-8 に固定してあり、`LANG` が未設定でも同じ結果になります。

疑似エージェントは本物と同じ `HttpTool` を使うので、Cookie と CSRF トークンの扱いも同じ経路を通ります。
ここが通っていれば、LLM を使った実行で出る差は装置の差ではなく表現の差だと言えます。

## 費用の目安

自作ループの1実行は、HTML条件でおよそ 2〜5 万入力トークン、JSON条件は仕様書を毎ターン送るため
（プロンプトキャッシュを使っていません）およそ 5〜15 万入力トークンです。
出力トークンはどちらも千〜数千です。シナリオ5本 × 条件2〜3 × N=10 で、
Sonnet 級のモデルなら数ドルから十数ドルの範囲に収まります。
正確な費用は `run.json` の `input_tokens` / `output_tokens` から計算してください。
参考実行（Claude Code）は `total_cost_usd` が記録されます。
