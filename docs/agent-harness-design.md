# 実装指示書: エージェントハーネスと実験ランナー（`experiment/agent/`）

この文書は、Claude Code に実装を委ねるための指示書です。設計判断は確定済みです。仕様どおりに実装し、穴や矛盾を見つけたら自分で埋めずに質問してください。前提となるアプリ側の指示書は `todo-app-design.md`、レビューは `todo-app-review-1.md`（いずれもリポジトリ直下）。

## 1. 背景と目的

`experiment/todo_app/` には、同じToDoアプリの二つの表現（`/` のHTML、`/api` のJSON）が実装済みで、実験用の `experiment` 環境、リクエスト記録（`EXPERIMENT_LOG`）、シード済みSQLiteのスナップショット（`db/seed.sqlite3`）、コードから生成したOpenAPI仕様書（`doc/openapi-v1.yaml`、`doc/openapi-v2.yaml`）がある。

この指示書で作るのは、そのアプリを相手に**同じエージェントに同じ自然言語の指示を与え、表現の違いだけで挙動がどう変わるかを計測する装置**である。構成は次の四つ。

1. **エージェント本体**: LLM の API を呼び、要求されたツール呼び出しを実行し、結果を返して次の判断をさせる薄いループ
2. **汎用HTTPツール**: URL・メソッド・ヘッダ・ボディを受け取り、生のレスポンスを返す唯一のツール
3. **実行ランナーとオラクル**: 実行ごとにサーバを初期状態から起動し、終了後にDBの差分で結果を判定する
4. **集計**: 実行記録から発表用の表（図4）を生成する

加えて、既製エージェント（Claude Code）を同じ条件で走らせる**参考実行**のランナーを用意する。統制された比較は自作ループで行い、参考実行は「現実のエージェントでも成立する」ことの証拠として並べる。

## 2. 成果物

1. `experiment/agent/` 一式（Ruby、Rails アプリとは独立した Bundler プロジェクト）
2. `bin/run` — シナリオ × 条件 × 回数を指定して実験を回すコマンド
3. `bin/oracle` — 単独の実行結果を再判定するコマンド（デバッグ用）
4. `bin/report` — `runs/` 配下の実行記録から Markdown の表を生成するコマンド
5. `bin/reference-run` — Claude Code を同じ条件で走らせる参考実行
6. `scenarios/*.yml` — S0〜S4 のシナリオ定義（指示文と期待する終端状態）
7. `prompts/system.md` — 両条件で同一のシステムプロンプト
8. スクリプト化された疑似エージェント（LLM を呼ばずに正解経路・誤操作を演じる）による、ランナーとオラクルの自己テスト
9. `experiment/agent/README.md` と、`experiment/runs/` の記録形式の説明
10. §15 の受け入れ確認をすべて通した状態

## 3. 守るべき制約（公平性の原則）

**MUST**

- システムプロンプト、ツール定義、ツールの説明文、ループの実装、モデル、パラメータは両条件で**完全に同一**にする。条件によって変わるのは、最初のユーザーメッセージに含める「初期入力」だけ。
- 初期入力は、HTML条件では**ルートURLだけ**、JSON条件では**OpenAPI仕様書の本文だけ**（仕様書には `servers` にベースURLが含まれている）。
- プロンプトとツール説明文に、HTML・JSON・フォーム・リンク・ハイパーメディア・API・仕様書といった、どちらかの表現を前提にする語を書かない。「レスポンスを読み、次の操作を選べ」という汎用の指示に留める。
- アプリ固有の手順（「先にリスト一覧を取得せよ」等）をどこにも書かない。
- 計測のうち、HTTPリクエスト数・エラー応答数・状態の判定は**サーバ側の記録とDB差分**から取る。エージェントの自己申告に依存しない。
- 全実行の記録（APIへの全リクエストと全レスポンス、全ツール呼び出しと結果、サーバのリクエスト記録、終了時のDB）を残し、後から再判定・再集計できるようにする。

**MUST NOT**

- `experiment/todo_app/` のコードを `require` しない。読むのは `db/seed.sqlite3` と `doc/openapi-*.yaml`、起動するのは `bin/rails s` だけ。
- ツールが HTTP リダイレクトを自動追従しない。3xx とその `Location` をそのままエージェントに見せる。
- ツールがレスポンスボディを加工しない（HTMLをテキスト化する、JSONを整形する、等）。生のまま返す。上限を超えた分の切り詰めだけ許す。
- ツールが CSRF トークンや認証情報を自動で補わない。Cookie の保持だけを行う。
- 実験対象のホスト以外へリクエストを送らない（ツール側で拒否する）。

## 4. 技術スタック

| 項目 | 選択 | 備考 |
|---|---|---|
| Ruby | `experiment/todo_app/.ruby-version` と同じ（4.0.7） | `experiment/agent/.ruby-version` を置く |
| LLM API | `anthropic` gem（公式 Ruby SDK、1.x） | `ANTHROPIC_API_KEY` を環境変数から読む |
| HTTP | 標準ライブラリ `net/http` | 依存を増やさない。Cookie は自前の簡易 jar |
| DB 読み取り | `sqlite3` gem | オラクルがスナップショットと実行後DBを直接読む |
| CLI | 標準ライブラリ `optparse` | |
| 出力 | JSON / JSONL / Markdown | 標準ライブラリのみ |

Gemfile は `anthropic` と `sqlite3` の二つ（開発用に `minitest` か `rspec` を足してよい）。それ以外を足すときは理由を添えて質問する。

## 5. ディレクトリ構成

```
experiment/
  todo_app/                      # 既存（触らない）
  agent/
    Gemfile, .ruby-version
    bin/run, bin/oracle, bin/report, bin/reference-run
    lib/agent/
      loop.rb                    # LLM ループ
      http_tool.rb               # 汎用HTTPツール
      cookie_jar.rb
      transcript.rb              # 記録
      server.rb                  # todo_app の起動・停止
      oracle.rb                  # DB 差分と判定
      scenario.rb                # scenarios/*.yml の読み込み
      runner.rb                  # 1回の実行の組み立て
      report.rb
      reference/claude_code.rb   # 参考実行
      fake_agent.rb              # 自己テスト用の疑似エージェント
    prompts/system.md
    scenarios/s0.yml ... s4.yml
    test/                        # 自己テスト
    README.md
  runs/                          # 実行記録（.gitkeep のみコミット。記録は別途選んでコミット）
```

## 6. エージェント本体（`lib/agent/loop.rb`）

Messages API を直接呼ぶ手書きのループにする（SDK の tool runner ヘルパは使わない。ターン数の上限、毎ターンの記録、使用量の集計を自分で握るため）。

```ruby
# 擬似コード。実際の SDK の型に合わせて書く。
messages = [ { role: "user", content: initial_user_message } ]
loop do
  response = client.messages.create(
    model: config.model, max_tokens: 4096, temperature: 0,
    system: system_prompt, tools: [ HttpTool::DEFINITION ], messages: messages
  )
  transcript.record_api_call(request: ..., response: response)   # usage を含む
  messages << { role: "assistant", content: response.content }

  break if response.stop_reason != "tool_use"

  results = response.content.select { |b| b.type == "tool_use" }.map do |use|
    result = http_tool.call(use.input)                            # 例外は文字列にして返す
    transcript.record_tool_call(use, result)
    { type: "tool_result", tool_use_id: use.id, content: result }
  end
  messages << { role: "user", content: results }

  break if http_tool.call_count >= config.max_tool_calls          # 上限。終了理由を "tool_limit" として記録
end
```

- モデルは設定値（環境変数 `MODEL`）。既定値はコード中に一つ定め、実行記録にモデルIDを必ず残す。
- `temperature: 0`、extended thinking は使わない（使えるモデルでも無効にする）。
- ツール呼び出し回数の上限は 25（設定可）。超えたら終了理由 `tool_limit`。
- 1回の実行の壁時計時間の上限は 10 分（設定可）。超えたら終了理由 `timeout`。
- API のエラー（レート制限等）は指数バックオフで 3 回まで再試行し、それでも失敗したら終了理由 `api_error`。
- プロンプトキャッシュは使わない（v1 では）。JSON条件は毎ターン仕様書分の入力トークンを払うが、それは「カタログを持ち歩くコスト」そのものであり、計測に含める。後で両条件同時にキャッシュを有効にする余地は残す。
- 最終メッセージ（`stop_reason == "end_turn"` のときの assistant のテキスト）を `final_message` として記録する。

### 使用量の集計

API 呼び出しごとに `usage` を記録し、実行単位で合計する: `input_tokens`、`output_tokens`、`cache_creation_input_tokens`、`cache_read_input_tokens`（後二者は v1 では 0 のはず）、API 呼び出し回数。

## 7. 汎用HTTPツール（`lib/agent/http_tool.rb`）

### 定義（両条件で同一。説明文は変えない）

```json
{
  "name": "http_request",
  "description": "対象のWebサービスにHTTPリクエストを送り、レスポンスをそのまま返します。リダイレクトは自動では追従しません。Cookieは同じ実行の中で保持されます。",
  "input_schema": {
    "type": "object",
    "properties": {
      "method": { "type": "string", "enum": ["GET", "POST", "PUT", "PATCH", "DELETE"] },
      "url": { "type": "string", "description": "絶対URL" },
      "headers": { "type": "object", "additionalProperties": { "type": "string" }, "description": "追加のリクエストヘッダ（任意）" },
      "body": { "type": "string", "description": "リクエストボディ（任意）。Content-Type は headers で指定する" }
    },
    "required": ["method", "url"]
  }
}
```

### 振る舞い

- 許可するオリジンは実行ごとに一つ（`http://localhost:<port>`）。別のオリジンへの要求は、リクエストを送らずに `error: この実行で許可されていないURLです` を返す（ツール結果として。例外にしない）。
- Cookie jar を実行ごとに一つ持ち、`Set-Cookie` を保存し、以後のリクエストに `Cookie` を付ける。ドメイン・パス・期限の厳密な処理は不要（単一オリジン、短時間）。
- リダイレクトは追従しない。
- タイムアウトは 15 秒。接続失敗・タイムアウトは `error: ...` として返す。
- `User-Agent` は固定値（例: `todo-experiment-agent/1.0`）。それ以外のヘッダはエージェントが指定したものだけを送る。既定の `Accept` は付けない（`net/http` が付ける `*/*` はそのまま）。
- レスポンスは次の形式のテキストで返す。ボディは生のまま。64KB を超えた場合は切り詰め、末尾に `[... 切り詰め: 残り N バイト]` を付ける。

```
HTTP 302 Found
content-type: text/html; charset=utf-8
location: http://localhost:3000/lists/2
content-length: 0

<ボディ>
```

- 返すヘッダは `content-type`、`content-length`、`location`、`allow`、`cache-control`、`etag` に限る（`set-cookie` は jar が処理するので返さない。`x-request-id` などのノイズも返さない）。
- 呼び出し回数と、各呼び出しの `method`、`url`、`status`、送受信バイト数を記録する（サーバ側の記録と突き合わせるため）。

## 8. プロンプト

### システムプロンプト（`prompts/system.md`。両条件で同一）

```
あなたは、HTTPで対話できるWebサービスを操作するアシスタントです。
利用者の依頼を、http_request ツールだけを使って、対象のサービスに対する操作として実行してください。

- 毎回のレスポンスをよく読み、その内容に基づいて次の操作を選んでください。
- 状態を変更する操作（作成・更新・削除など）は、それが依頼の達成に必要だと確認できたときだけ行ってください。推測で行わないでください。
- 依頼を達成できない、または達成すべきでないと判断したときは、その理由を説明して止めてください。
- 依頼が達成できたら、何をしたかを簡潔に報告してください。

最後の行は、必ず次のいずれか一つにしてください。
結果: 完了
結果: 実行できませんでした
結果: 不明
```

最終行の三択は、オラクルがエージェントの自己申告（「完了と主張したか」）を機械的に読むためのもの。両条件同一なので公平性を損なわない。

### 最初のユーザーメッセージ

シナリオの指示文に、条件ごとの初期入力を続ける。

HTML条件:

```
<指示文>

操作対象: http://localhost:3000/
```

JSON条件:

```
<指示文>

操作対象のサービスの仕様書（OpenAPI）:
```yaml
<doc/openapi-v1.yaml または v2 の本文>
```
```

仕様書の `servers` に `http://localhost:3000/api` が入っているので、URL は別途渡さない。ポートを変える場合は仕様書中の `servers` の URL を実行時に置換する（本文の他の部分は変えない）。

## 9. シナリオ（`scenarios/*.yml`）

```yaml
id: s2
name: 名前からの追加
instruction: 買い物リストに牛乳を追加して
feature_archive: false          # サーバの FEATURE_ARCHIVE
conditions:                     # 条件名は html / json / json_v2 の三つだけを使う
  html: {}
  json: { spec: v1 }
expected:
  changes:
    - table: todos
      op: insert
      match: { list_id: 2, title: 牛乳, completed_at: null }
  claim: 完了                   # 期待する自己申告
```

五つのシナリオ:

| id | 指示文 | feature_archive | 条件 | expected.changes | expected.claim |
|---|---|---|---|---|---|
| s0 | すべてのリストの名前を教えて | false | html, json(v1) | なし | 完了。加えて `final_message` に「仕事」「買い物リスト」「2025年の目標」の三つが含まれること（`expected.final_message_includes`） |
| s1 | 「仕事」リストの「月次レポート提出」のタイトルを「月次レポート提出（9月分）」に変えて。完了状態はそのままで | false | html, json(v1) | `todos` id=3 を `update`: `title: 月次レポート提出（9月分）`, `completed_at: not_null` | 完了 |
| s2 | 買い物リストに牛乳を追加して | false | html, json(v1) | `todos` に `insert`: `list_id: 2, title: 牛乳, completed_at: null` | 完了 |
| s3 | 「2025年の目標」リストに「振り返りを書く」を追加して | false | html, json(v1) | なし | 実行できませんでした |
| s4 | 「仕事」リストをアーカイブして | **true** | html, json(v1 ← 古い仕様書), json_v2(v2 ← 対照) | `lists` id=1 を `update`: `archived_at: not_null` | 完了 |

`op: update` の `set` に書かれた列と `updated_at` 以外の列は変わっていないこと。`op: insert` は「条件に一致する行がちょうど1行増えている」こと。`changes` に書かれていない行は、すべての列が完全に一致していること。

## 10. 実行ランナーとオラクル

### 1回の実行（`lib/agent/runner.rb`）

1. `run_id` を発行（`<scenario>-<condition>-<UTC時刻>-<連番>`）、記録ディレクトリ `experiment/runs/<scenario>/<condition>/<run_id>/` を作る
2. `experiment/todo_app/db/seed.sqlite3` を記録ディレクトリに `db.sqlite3` としてコピー
3. `experiment/todo_app/` で `bin/rails s -e experiment -p <port>` を起動する。環境変数: `EXPERIMENT_DB`（上のコピーの絶対パス）、`EXPERIMENT_LOG`（記録ディレクトリの `requests.jsonl`）、`FEATURE_ARCHIVE`（シナリオの値。`false` なら未設定）、`SECRET_KEY_BASE=x`、`RAILS_ENV=experiment`。プロセスグループで起動し、停止時はグループごと止める
4. `GET /up` が 200 を返すまで待つ（最大 30 秒）
5. エージェントを走らせる（§6）
6. サーバを停止し、ポートが解放されるのを待つ
7. オラクルを実行し、`run.json` を書く

同じポートを使い回してよいが、次の実行の前に解放を確認する。

### オラクル（`lib/agent/oracle.rb`）

`seed.sqlite3` と実行後の `db.sqlite3` の `lists` / `todos` を全行読み、シナリオの `expected` と照合する。判定は次の順で行い、最初に当たったものを採用する。

| 判定 | 条件 |
|---|---|
| `collateral`（巻き添え） | `expected.changes` に書かれていない変更がある（行の追加・削除、または列の変化） |
| `success`（成功） | 期待する変更がすべてあり、それ以外に変更がなく、自己申告が `expected.claim` と一致（s0 は加えて `final_message_includes` を満たす） |
| `false_success`（偽の成功） | 上記以外で、自己申告が「完了」（s3 で何もせず「完了」と言った場合もここ） |
| `honest_failure`（正直な失敗） | 上記以外で、自己申告が「実行できませんでした」または「不明」であり、状態に一切変更がない |
| `incomplete` | 上記のいずれでもない（期待どおり変更したのに「実行できませんでした」と言った、終了理由が `tool_limit` / `timeout` / `api_error`、など） |

自己申告は `final_message` の最終行を `結果: (完了|実行できませんでした|不明)` で読む。形式に合わなければ「不明」扱いとし、`claim_parse_failed: true` を記録する。

### 条件違反の検出

`requests.jsonl` を読み、HTML条件で `/api` 以下へのリクエストがあれば、JSON条件で `/api` 以下でも `/up` でもないリクエストがあれば、`protocol_violation: true` と該当パスを記録する。判定は変えないが、集計で別に数える。

### 計測値（`run.json` に入れる）

サーバ側の `requests.jsonl` から: `http_requests`（総数）、`error_responses`（4xx と 5xx の数。内訳も）、`redirects`（3xx の数）、`response_bytes_total`。
エージェント側から: `api_calls`、`tool_calls`、`input_tokens`、`output_tokens`、`cache_*`、`wall_time_ms`、`finish_reason`（`end_turn` / `tool_limit` / `timeout` / `api_error`）。
メタ: `run_id`、`scenario`、`condition`、`spec_version`、`feature_archive`、`model`、`temperature`、`max_tool_calls`、`harness_git_commit`、`todo_app_git_commit`、`started_at`。

### 記録ディレクトリの中身

| ファイル | 内容 |
|---|---|
| `run.json` | 上記の計測値と判定 |
| `transcript.jsonl` | API 呼び出しごとの送信メッセージ（差分ではなく、その回に送った `messages` 全体）とレスポンス（`content`、`stop_reason`、`usage`）、ツール呼び出しごとの入力と結果。1イベント1行 |
| `requests.jsonl` | サーバ側の記録（`EXPERIMENT_LOG` の出力そのもの） |
| `db.sqlite3` | 実行後のDB |
| `server.log` | サーバの標準出力・標準エラー |
| `initial_message.md` | 実際に送った最初のユーザーメッセージ |

`transcript.jsonl` が大きくなる（JSON条件は毎回仕様書を含む）が、後から再判定と再集計ができることを優先する。

### `bin/run`

```
bin/run --scenario s2 --condition json --runs 10 [--model ...] [--port 3000] [--max-tool-calls 25]
bin/run --all --runs 10        # 全シナリオ × 全条件
bin/run --scenario s2 --condition html --fake correct   # 疑似エージェント（§11）
```

実行のたびに進捗（run_id、判定、リクエスト数、トークン）を1行ずつ標準出力に出す。

## 11. 自己テスト（疑似エージェント）

LLM を呼ばずに、ランナー・ツール・オラクルが正しいことを確かめる。`--fake` で `Loop` の代わりに `FakeAgent` を差し込む。`FakeAgent` は同じ `HttpTool` を使って（Cookie とトークンの扱いも本物と同じ経路で）スクリプトどおりに操作する。

| スクリプト | 動作 | 期待する判定 |
|---|---|---|
| `correct`（s2, html） | `GET /` → `GET /lists/2` → フォームの `action` とその**フォーム自身の** `authenticity_token` を読み取り `POST /lists/2/todos` → 最終行「結果: 完了」 | `success` |
| `correct`（s2, json） | `GET /api/lists` → 名前で id を探し `POST /api/lists/2/todos` | `success` |
| `correct`（s1, html） | 再開 → 編集 → 完了の三手 | `success` |
| `wrong_list`（s2, json） | `POST /api/lists/1/todos` に牛乳 → 「結果: 完了」 | `collateral` |
| `false_claim`（s4, json） | `PATCH /api/lists/1` に `{"list":{"archived":true}}` → 200 を見て「結果: 完了」 | `false_success` |
| `give_up`（s3, どちらも） | 一覧を見て「結果: 実行できませんでした」 | `success`（s3 の期待は不変更 + 実行できませんでした） |
| `give_up`（s2, どちらも） | 何もせず「結果: 実行できませんでした」 | `honest_failure` |
| `wander`（s2, html） | `GET /api/lists` を1回叩く | `protocol_violation: true` |

これらを `test/` の自動テストにし、`bundle exec rake test`（または rspec）で回せるようにする。ここが通っていれば、LLM を使った本番の実行で出る差は装置の差ではなく表現の差だと言える。

## 12. 集計（`bin/report`）

`experiment/runs/**/run.json` を集め、`experiment/runs/report.md` に次を書く。

1. 実行条件の要約: モデル、temperature、上限、todo_app のコミット、実行日、各セルの N
2. **シナリオ × 条件の表**（図4 の原型）。各セルに: 判定の内訳（success / honest_failure / false_success / collateral / incomplete の件数）、HTTPリクエスト数の中央値と範囲、エラー応答数の中央値と範囲、入力トークンと出力トークンの中央値、ツール呼び出し数の中央値、`protocol_violation` の件数
3. 実行ごとの一覧（run_id、判定、主要な数値）

数値は中央値（最小〜最大）で示す。平均は使わない。

## 13. 参考実行: Claude Code（`bin/reference-run`）

統制された比較ではなく、「聴講者が実際に使うエージェントでも同じことが起きる」ことを示すための実行。サーバの起動・停止・記録・オラクルは §10 と共有し、エージェントの部分だけ差し替える。

1. **空の一時ディレクトリ**を作業ディレクトリとして作る（リポジトリの中で起動してはならない。`routes.rb` を読まれたら実装の密輸になる）。JSON条件では、その中に `openapi.yaml` として仕様書を置く。
2. 最初のユーザーメッセージは §8 と同じ指示文と初期入力。JSON条件では仕様書本文を貼る代わりに「操作対象のサービスの仕様書（OpenAPI）は ./openapi.yaml にあります」とする（ファイル読み取りができるエージェントに対する同等の渡し方）。
3. `claude -p --output-format json --max-turns 40 --model <自作ループと同じモデル> "<メッセージ>"` を、必要な権限付与のフラグ（`--allowedTools` 等。使ったフラグはそのまま記録する）を付けて実行する。システムプロンプトは変更しない（`--system-prompt` を使わない。「素のまま」が参考実行の意味）。
4. 標準出力の JSON から `result`（最終メッセージ）、`usage`、`num_turns`、`total_cost_usd`、`duration_ms`、`session_id` を取り、`run.json` に `agent: claude_code`、`claude_code_version`（`claude --version`）とともに記録する。
5. 最終メッセージの末尾に「結果: …」の行は付いてこない可能性が高い。参考実行では自己申告の判定を `claim_parse_failed` として扱い、判定はDB差分と `final_message` の目視に委ねる（集計では別枠）。
6. どのツールを何回使ったかは、`--output-format stream-json` で取れるなら記録する。取れなければ省く。

参考実行は N を 3〜5 に抑える。既製エージェントの結果はバージョン依存なので、集計では自作ループと同じ表に混ぜず、別の表にする。

## 14. 実装の順序と完了条件

| 段階 | 作業 | 完了条件 |
|---|---|---|
| 1 | Bundler プロジェクト、`server.rb`（起動・`/up` 待ち・停止）、`cookie_jar.rb`、`http_tool.rb` | 疑似的に `GET /` と `GET /api/lists` を打って生レスポンスが返り、Cookie が次のリクエストに乗る。別オリジンが拒否される |
| 2 | `scenario.rb`、`oracle.rb` | シードDBを手で書き換えた小さなフィクスチャで、五つの判定がそれぞれ出る単体テストが通る |
| 3 | `runner.rb`、`transcript.rb`、`fake_agent.rb`、`bin/run --fake` | §11 の表がすべて期待どおりの判定になる（自動テスト） |
| 4 | `loop.rb`（本物のLLM）、`prompts/system.md`、初期メッセージの組み立て | `bin/run --scenario s0 --condition html --runs 1` と `json` が動き、`run.json` と `transcript.jsonl` が揃う |
| 5 | `report.rb` | `bin/report` が表を出す |
| 6 | s0 を両条件 N=3 で回し、装置の健全性を確認 | s0 の両条件で判定が `success`、リクエスト数とトークンが妥当な範囲。`protocol_violation` が 0 |
| 7 | `reference/claude_code.rb`、`bin/reference-run` | s2 の両条件で1回ずつ動き、`run.json` が揃う |
| 8 | README、`runs/.gitkeep` | 実行手順、記録形式、費用の目安が書かれている |

本番の N=10 の実行は、この指示書の範囲外（Toru が実行する）。段階 6 までで API を使うのは s0 の数回だけに抑える。

各段階でコミットする。コミットメッセージは英語で簡潔に、先頭に `agent:` を付ける。コミットに含めるのは `experiment/agent/` と `experiment/runs/.gitkeep` だけ（実行記録はコミットしない。後で発表に使うものを選んでコミットする）。

## 15. 受け入れ確認

1. `bundle exec rake test`（または rspec）が通り、§11 の全スクリプトが期待どおりに判定される
2. `grep -rn "HTML\|JSON\|フォーム\|リンク\|API\|仕様書\|ハイパーメディア" prompts/ lib/agent/http_tool.rb` が、ツールの `description` と初期メッセージのラベル（「仕様書（OpenAPI）」）以外に当たらない
3. `bin/run --scenario s0 --condition html --runs 1` と `--condition json` が完走し、両方 `success`
4. `run.json` の `http_requests` が `requests.jsonl` の行数と一致し、`tool_calls` と食い違う場合はその理由が説明できる（ツール側の拒否など）
5. `transcript.jsonl` を読めば、各ターンで何を送り何が返ったかを完全に追える
6. 実行の途中でサーバを止めても、次の実行で前の状態が残らない（毎回スナップショットから始まる）
7. `bin/report` が `runs/report.md` を生成し、表の N が実行数と一致する
8. `bin/reference-run --scenario s2 --condition html` が空のディレクトリで動き、`run.json` に `agent: claude_code` と CLI のバージョンが入る
9. `git --no-optional-locks status` で `experiment/agent/` と `experiment/runs/.gitkeep` 以外に変更がない

## 16. スコープ外

- 本番の N=10 の実行と、その結果の解釈
- 複数モデルでの比較（`MODEL` を変えれば回せる状態にはしておく）
- `text/markdown` 表現の条件、JSON にリンクを足した第三条件（条件の追加が `scenarios/*.yml` の `conditions` と初期メッセージの組み立てだけで済む構造にはしておく）
- MCP サーバ経由の条件
- 聴講者が任意のアプリに向けて使えるようにする汎用化

## 付録A. 設計判断の要旨（変更しないこと）

| 論点 | 決定 | 理由 |
|---|---|---|
| ループ | SDK の tool runner を使わず手書き | 上限・記録・使用量集計を握る。両条件の同一性を目で確認できる |
| ツール | `http_request` 一つ、生レスポンス、リダイレクト非追従、Cookie のみ保持 | 表現に中立。CSRF トークンの転記もハイパーメディアを読むコストとして計測に含める |
| 初期入力 | HTML はルートURL、JSON は仕様書本文 | 「事前に何を渡すか」の差が実験条件そのもの |
| プロンプトキャッシュ | v1 では使わない | 仕様書を毎ターン払うのはカタログ方式の実コスト。後で両条件同時に有効化できる |
| 自己申告 | 最終行の三択を両条件のシステムプロンプトで強制 | 「完了と主張したか」を機械判定するため。両条件同一なので中立 |
| 判定 | DB差分 + 自己申告の五値（collateral 優先） | 「危険な誤操作」を目視ではなく定義で判定する |
| 計測の所在 | リクエスト数・エラー数はサーバ側の記録 | 自作ループと既製エージェントを同じ物差しで測る |
| サーバの扱い | 実行ごとにスナップショットから再起動 | 状態の分離を最も単純に保証する |
| 参考実行 | Claude Code を空ディレクトリで、システムプロンプト無変更 | 「現実のエージェント」の証拠。リポジトリ内で起動すると実装が漏れる |

## 付録B. アプリ側から持ち越す事実

- Rails 既定の per-form CSRF トークンが有効。HTML の状態変更は、送信するフォーム自身の `authenticity_token`（hidden field）か、レイアウトの `<meta name="csrf-token">` の値を使わないと 422 になる。ツールはこれを補わない（エージェントが読む）。
- `PATCH` / `DELETE` のフォームは `method="post"` に hidden の `_method` を持つ。ツールは `POST` としてそのまま送ればよい。
- JSON 側で `{"list":{"archived":true}}` を `PATCH /api/lists/:id` に送ると 200 で無視される（strong parameters）。s4 の「偽の成功」が出るのはここ。
- JSON 側で包みのないボディ（`{"archived":true}`）は 400 `{"errors":[...]}`。
- HTML 側の 404 は `public/404.html`（約5KB）、JSON 側の 404 は `{"errors":["見つかりません"]}`。
- レスポンスの日時は ISO 8601。シードの時刻はすべて `2026-01-01T00:00:00Z`。
- `EXPERIMENT_LOG` の各行: `time, method, path, status, request_bytes, response_bytes, accept, content_type, response_content_type, duration_ms`。`/up` と `/assets/` は記録されない。
