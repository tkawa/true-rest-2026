# 実装指示書: 汎用の入口 `bin/agent`（`experiment/agent/`）

この文書は、Claude Code に実装を委ねるための指示書です。前提は `agent-harness-design.md`（ハーネスの設計）と `experiment/agent/NOTES.md`（これまでの経緯）。設計判断は確定済みで、穴や矛盾を見つけたら自分で埋めずに質問してください。

## 1. 背景と目的

CFP は「エージェントを自分のアプリケーションに向ければ、その設計がエージェントからどう見えるか、どこで詰まるかを確かめられます」と約束している。いまのハーネスは、ループ（`Loop`）と汎用HTTPツール（`HttpTool`）は対象を選ばないが、入口の `bin/run` がサーバの起動・シナリオ・オラクルまで抱えていて、`todo_app` 以外に向けられない。

作るのは、**ループとツールだけを使う小さな入口**。任意の URL（ハイパーメディア方式）または任意の OpenAPI 仕様書（カタログ方式）と、自然言語の指示を受け取り、実験と同じシステムプロンプト・同じツール・同じ初期メッセージの組み立てで一回だけ走らせ、記録を残す。サーバの管理も、成否の自動判定もしない。判定は人が記録を読んで行う。

これで発表では「ループとツールは汎用です。URL か仕様書と指示文を差し替えれば、自分のアプリに向けて動きます。成否の自動判定は今回の ToDo アプリ専用です」と言える。

## 2. 成果物

1. `bin/agent` — 汎用の入口
2. `lib/agent/adhoc.rb`（名前は任意）— 入口の組み立て。`Loop` と `HttpTool` は**変更せずに**使う
3. `InitialMessage` の小さな一般化（§5）。既存の `bin/run` の出力は**1バイトも変わらない**こと
4. `HttpTool` への「固定ヘッダ」の追加（§6）。既定では空で、`bin/run` の挙動は変わらない
5. 記録の秘匿処理（§7）
6. テスト（§9）と README の節（§10）

## 3. 守るべき制約

**MUST**

- システムプロンプト（`prompts/system.md`）、ツール定義、`Loop` の実装は一切変えない。`bin/agent` で走らせたエージェントは、実験で走らせたエージェントと同じものである。
- 初期メッセージの形式は実験と同じにする。URL を渡したときは「操作対象: <URL>」、仕様書を渡したときは「操作対象のサービスの仕様書（OpenAPI）:」に本文を続ける。同じ入力を `bin/run` に与えたときと同じ文字列になる（§9 で検証）。
- 許可するオリジンは実行ごとに一つ。URL からはそのオリジン、仕様書からは `servers[0].url` のオリジン。ツールの単一オリジン制限はそのまま働く。
- 記録は実験のデータセット（`experiment/runs/`）に**混ぜない**。既定の置き場は `experiment/runs-scratch/adhoc/`（gitignore 済み）。

**MUST NOT**

- アプリ固有の手順や表現に依存する語をプロンプトに足さない（`--hint` のような変種も作らない。これは実験の装置ではなく、実験と同じエージェントをそのまま向けるための入口）。
- `Authorization` や `Cookie` など、利用者が渡した認証情報の値を記録に残さない（§7）。
- 対象サーバを起動・停止しない。動いているものに向けるだけ。

## 4. コマンドライン

```
bin/agent --url http://localhost:3000/ --task "買い物リストに牛乳を追加して"
bin/agent --spec path/to/openapi.yaml --task "買い物リストに牛乳を追加して"
```

| オプション | 意味 |
|---|---|
| `--url URL` | ハイパーメディア方式の入口。`--spec` と排他 |
| `--spec PATH` | カタログ方式の入口。ファイルの本文をそのまま初期メッセージに埋め込む。`--url` と排他 |
| `--task TEXT` | 指示文。必須。`--task-file PATH` でファイルからも読める |
| `--origin ORIGIN` | 許可オリジンの上書き。仕様書の `servers` が相対 URL・複数・不在のときに使う |
| `--header "Name: value"` | 全リクエストに付ける固定ヘッダ。繰り返し可（認証用。§6） |
| `--out DIR` | 記録の置き場。既定 `../runs-scratch/adhoc/<UTC時刻>/` |
| `--model`, `--max-tool-calls`, `--timeout` | `bin/run` と同じ。環境変数の既定も同じ |
| `--dry-run` | API を呼ばず、組み立てた初期メッセージと許可オリジンを表示して終わる |
| `--quiet` | 進行の逐次表示を止める |

`--url` と `--spec` のどちらも無い、または両方ある場合はエラー。`--spec` で `servers[0].url` が絶対 URL でなく `--origin` も無い場合は、その旨を言ってエラー。

## 5. 初期メッセージの一般化

いまの `InitialMessage` は `todo_app` の `doc/openapi-<version>.yaml` を読み、`http://localhost:3000/` を実行時のオリジンに置換している。これを、**本文と URL を外から与えられる**形に一段だけ一般化する。

- `bin/run` からは従来どおり（アプリのパスとバージョンから本文を読み、ポート置換を行う）
- `bin/agent` からは、`--url` の文字列、または `--spec` の本文をそのまま渡す。**置換はしない**（利用者の仕様書をハーネスが書き換えてはいけない）

両方が同じ整形関数（「操作対象: …」／「操作対象のサービスの仕様書（OpenAPI）:」＋コードフェンス）を通ること。既存のシナリオに対する出力が変わっていないことを、`experiment/runs/` に残っている `initial_message.md` との一致で確認する（§9）。

## 6. 固定ヘッダ

実際のアプリには認証がある。`--header` で渡されたヘッダを、`HttpTool` が全リクエストに付ける。

- `HttpTool.new(allowed_origin:, cookie_jar:, default_headers: {})` のように既定空で追加する。`bin/run` は渡さないので挙動は変わらない
- エージェントが同名のヘッダを指定した場合は、エージェントの指定を優先する（利用者が渡した `Authorization` をエージェントが上書きできる。上書きした事実は記録に残るので追える）
- Cookie jar は従来どおり動く。`--header "Cookie: ..."` を渡した場合、jar が `Set-Cookie` で更新した値と衝突しうるが、単純に「jar に値があれば jar、なければ固定ヘッダ」とする
- CSRF トークンなどの自動補完はしない（原則どおり）

## 7. 記録と秘匿

記録ディレクトリには実験と同じ形式で残す。

| ファイル | 内容 |
|---|---|
| `run.json` | 条件（`url` または `spec_path` と `spec_sha256`、`origin`、`model`、`system_prompt_sha256`、固定ヘッダの**名前だけ**）、計測（`api_calls`、`tool_calls`、トークン、`wall_time_ms`、`finish_reason`）、`final_message`、`claim`（最終行から。オラクルの `claim` 読み取りを流用）、`tool_call_log` |
| `transcript.jsonl` | 実験と同じ |
| `initial_message.md` | 実際に送った初期メッセージ |

秘匿の規則。`--header` で渡された値は、`run.json`・`transcript.jsonl` のどこにも書かない。`transcript.jsonl` の `api_call` にはエージェントへ送ったメッセージ全体が入るが、固定ヘッダはツール側で付けるのでメッセージには現れない。ただし、エージェントが自分で `Authorization` や `Cookie` を `headers` に指定した場合は `tool_use` の入力に現れるので、記録時に `Authorization` / `Cookie` / `Proxy-Authorization` / `X-Api-Key` の値を `<REDACTED>` に置き換える（`Sanitizer` に規則を足す）。ツールの結果の中の `set-cookie` は既に返していないので追加の処理は不要。

サーバ側の記録は無いので、`run.json` の `http_requests` は書かない（`tool_call_log` の件数で代用できるが、名前を分けて `client_side_requests` とし、サーバ側の数と混同させない）。

## 8. 進行の表示

既定で、ツール呼び出しごとに一行を標準出力に出す。

```
→ GET  http://localhost:3000/                       200  2215B
→ GET  http://localhost:3000/lists/2                200  4131B
→ POST http://localhost:3000/lists/2/todos          302     0B
→ GET  http://localhost:3000/lists/2                200  4205B
```

終わったら空行を置いて `final_message` をそのまま出し、最後に記録ディレクトリのパスと、API 呼び出し数・入力／出力トークンを一行で出す。発表でこの画面をそのまま見せられる密度にする。`--quiet` で行の表示だけ止める。

## 9. テスト

- **同一性**: `bin/run` が s2 の html / json 条件で組み立てる初期メッセージと、同じ URL／同じ仕様書本文を `bin/agent` に与えたときの初期メッセージが、文字列として一致する。`experiment/runs/s2/html/*/initial_message.md` と `s2/json/*/initial_message.md` のいずれか一つと比較するのが簡単（ポートは記録に合わせる）
- **既存への無影響**: 既存の全テストが通り、`bin/run --fake correct --scenario s2` の `initial_message.md` が変更前と一致する
- **オリジン導出**: 仕様書の `servers[0].url` からの導出、`--origin` の上書き、相対 URL でのエラー
- **固定ヘッダ**: 付くこと、エージェント指定が優先されること、jar が優先されること
- **秘匿**: `Authorization` 付きで走らせた記録に値が残らないこと（`FakeAgent` に一手だけ `Authorization` を指定させる）
- **通し**: テスト内で `Server` を使って `todo_app` を起動し、`FakeAgent` の `correct` を `bin/agent` の組み立て（`Adhoc`）経由で走らせ、`runs-scratch` 側に記録が出ること

## 10. README に足す節

「自分のアプリに向ける」の節を `experiment/agent/README.md` に足す。

- 二つのコマンド例（URL と仕様書）
- 動いている `todo_app` に向けて s2 を再現する手順（`bin/rails s -e experiment` の起動から）
- 認証が要るアプリでの `--header` の使い方と、値が記録に残らないこと
- 成否の判定は自分で行うこと。`final_message` の最終行と `tool_call_log` を読む
- 実験のデータセットには混ざらないこと（`runs-scratch/`）

## 11. 受け入れ確認

1. `bundle exec rake test` が通る（§9 を含む）
2. `todo_app` を手で起動し、`bin/agent --url http://localhost:3000/ --task "買い物リストに牛乳を追加して"` が、実験の s2/html と同じ 4 リクエストの経路で完遂する（API を 1 回使う）
3. `bin/agent --spec ../todo_app/doc/openapi-v1.yaml --task "買い物リストに牛乳を追加して"` が、実験の s2/json と同じ 2 リクエストで完遂する（API を 1 回使う）
4. `--dry-run` の出力が、2・3 の `initial_message.md` と一致する
5. `--header "Authorization: Bearer dummy"` を付けて 2 を再実行し、`grep -r dummy runs-scratch/` が何も返さない
6. `experiment/runs/` に変化がない。`git --no-optional-locks status` で `experiment/agent/` 以外に変更がない
7. 既存の `system_prompt_sha256` が変わっていない（`prompts/system.md` に触れていないことの確認）

## 12. スコープ外

- 成否の自動判定（オラクル）。対象アプリの DB に触れないので不可能で、それが正しい
- 参考実行（Claude Code）の汎用版。作らない
- 複数オリジン、リダイレクトの自動追従、認証フローの自動化
- 仕様書を URL から取得する機能（利用者が `curl` で落として `--spec` に渡す）
