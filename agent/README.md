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
bin/reference-run --scenario s2 --condition html --hint  # 前提の一行を足した変種
bin/report                 # 疑似エージェントの実行は除外される
bin/report --include-fake  # 装置の確認用に含める
bin/oracle --run ../runs/s2/json/<run_id>
```

## 自分のアプリに向ける

ループとツールは対象を選びません。動いているサービスに、実験と同じエージェントを一回だけ向けられます。
サーバの起動も成否の判定もしません。判定は記録を読んで自分で行ってください。

```sh
bin/agent --url http://localhost:3000/ --task "買い物リストに牛乳を追加して"
bin/agent --spec path/to/openapi.yaml --task "買い物リストに牛乳を追加して"
```

| オプション | 意味 |
|---|---|
| `--url` | ハイパーメディア方式の入口。`--spec` と排他 |
| `--spec` | カタログ方式の入口。ファイルの本文をそのまま初期メッセージに埋め込む |
| `--task` / `--task-file` | 指示文。どちらか必須 |
| `--origin` | 許可オリジンの上書き。仕様書の `servers` が相対URLや不在のときに使う |
| `--header 'Name: value'` | 全リクエストに付ける固定ヘッダ（繰り返し可） |
| `--out` | 記録の置き場。既定は `experiment/runs-scratch/adhoc/<UTC時刻>/` |
| `--dry-run` | APIを呼ばず、初期メッセージと許可オリジンを表示する |
| `--quiet` | 進行の逐次表示を止める |

`--model`、`--max-tool-calls`、`--timeout` は `bin/run` と同じで、環境変数の既定も共通です。

### 実験の S2 を手元で再現する

`experiment/todo_app/` でサーバを起動します。

```sh
cp db/seed.sqlite3 /tmp/run.sqlite3
EXPERIMENT_DB=/tmp/run.sqlite3 SECRET_KEY_BASE=x bin/rails s -e experiment -p 3000
```

`experiment/agent/` から向けます。

```sh
bin/agent --url http://localhost:3000/ --task "買い物リストに牛乳を追加して"
bin/agent --spec ../todo_app/doc/openapi-v1.yaml --task "買い物リストに牛乳を追加して"
```

前者は4リクエスト、後者は2リクエストで終わります。実験の S2 と同じ経路です。

### 認証が要るアプリ

`--header` で渡したヘッダを、全リクエストに付けます。

```sh
bin/agent --url https://app.example.com/ --header "Authorization: Bearer $TOKEN" --task "…"
```

**渡した値は記録に残りません。** `run.json` にはヘッダの名前だけが入ります。
エージェントが自分で `Authorization`、`Cookie`、`Proxy-Authorization`、`X-Api-Key` を指定した場合も、
記録では値が `<REDACTED>` になります（ツール呼び出しの入力と、APIに送った会話履歴の両方）。
CSRFトークンの自動補完はしません（実験と同じ原則）。

伏せるのはヘッダの値だけです。**指示文（`--task`）はそのまま記録されます。**
指示文に秘密を書かないでください。

エージェントが同名のヘッダを指定したときは、エージェントの指定が優先されます。
Cookie は、jar に値があればそちらが固定ヘッダより優先されます。

### 成否の判定

自動判定はしません。対象アプリのDBに触れないので原理的にできません。
`run.json` の `final_message`（最終行が `結果: 完了` などになります）と `tool_call_log` を読んでください。
`claim` に最終行の読み取り結果が入ります。形式に合わなかった場合は `null` です。

### 実験のデータセットとは分かれています

記録は `experiment/runs-scratch/` に置かれ、`.gitignore` で除外されています。
`bin/report` が読む `experiment/runs/` には混ざりません。

## シナリオ

| id | 内容 | feature_archive | 条件 |
|---|---|---|---|
| s0 | すべてのリストの名前を教えて | false | html, json |
| s1 | 完了済みのToDoのタイトルを変える（完了状態はそのまま） | false | html, json |
| s2 | 名前で指したリストにToDoを追加する | false | html, json |
| s3 | アーカイブ済みのリストにToDoを追加する（できない） | false | html, json |
| s4 | リストをアーカイブする | **true** | html, json（古い仕様書）, json_v2（対照）, json_terse（警告文なし）, json_terse_nocontent（警告文なし + 更新が 204） |
| s5 | 上限を超えるタイトルへの変更（途中で失敗する多段の編集）。`feature_title_limit: true` | false | html, json（`v1-titlelimit`） |
| s6 | ToDo を別のリストに移す（操作が存在しない） | false | html, json, json_terse, json_terse_nocontent |
| s7 | 「経費精算」の期限を明後日にする。`seed: due`、`feature_due: true`、`today: 2026-03-04` | false | html, json（`v1-due`）, json_situated（`v1-due-situated`、`API_SITUATED=1`） |
| s8 | 「仕事」リストの期限切れをすべて明日に延ばす。設定は s7 と同じ | false | html, json, json_situated |

条件を足すときは `scenarios/*.yml` の `conditions` に書き足します。
条件ごとにサーバへ渡す環境変数は `server_env` に書きます（指定できるキーは `UPDATE_NO_CONTENT` と `API_SITUATED`）。`run.json` に `server_env` と `feature_title_limit` として記録します。

期限のシナリオは yml に `seed`（`default` か `due`。`due` は `db/seed-due.sqlite3` から始める）、`feature_due`（`FEATURE_DUE=1`）、`today`（`EXPERIMENT_TODAY`）を書きます。`feature_due: true` なら `today` が必須です。`run.json` に `seed`、`feature_due`、`today` として記録します。

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

参考実行（Claude Code）は素のシステムプロンプトで動かすので「結果: …」の行が付きません。
集計では自己申告を読まず、DB差分だけで `success` / `no_change` / `collateral` の三つに分けます。

| 判定 | 条件 |
|---|---|
| `collateral` | 期待に書かれていない変更がある |
| `success` | 期待する変更がすべてあり、それ以外に変更がない |
| `no_change` | 期待する変更が入っていない |

自作ループと参考実行を横に並べて読めるのは、サーバ側のHTTPリクエスト数だけです。
ツール呼び出しの数え方が違います（自作ループは `http_request` の回数、参考実行は CLI が使った全ツールの回数）。

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

参考実行（Claude Code）の `run.json` には、`tool_calls_by_name`、`response_model`、
`permission_mode`、`api_key_source`、`available_tools` も入ります。
既製エージェントは自前の認証で動かすので、ハーネスの `ANTHROPIC_API_KEY` は子プロセスに渡しません。

`experiment/runs/` は公開データセットとしてコミットしてあります。説明は
[runs/README.md](../runs/README.md) を見てください。取った実行をすべて残す方針です。

試し打ちは `RUNS_DIR=../runs-scratch` に向けてください（`experiment/.gitignore` で除外してあります）。

条件を変える前に取った予備実行は `experiment/runs-pilot/` に置き、本番の集計から外します。

別モデルでの追試は `experiment/runs-<モデルID>/` に置きます。
現在は `experiment/runs-claude-fable-5-1/`（別モデルでの追試）と
`experiment/runs-claude-sonnet-5-cli-2.1.283/`（参考実行の交絡の切り分け）があります。
データセットカードは各ディレクトリの README です。
本番と並べて見るには `--against` を使います。

```sh
RUNS_DIR=../runs-claude-fable-5-1 bin/report --against ../runs
```

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
