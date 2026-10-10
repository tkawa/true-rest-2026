# todo_app

Kaigi on Rails 2026 の発表「真のREST 2026」で使う比較実験用のToDoアプリです。
同じコントローラを二つのスコープにマウントし、HotwireのHTMLとJSON APIという二つの表現を、
同じ業務ロジックの上に並べています。

- HTML表現: `/` 以下
- JSON表現: `/api` 以下（`format` は `:json` に固定）

エージェントのハーネスや実行ランナーはこのディレクトリには含まれません。

## 必要なもの

- Ruby 4.0.7（`.ruby-version` を参照）
- SQLite

```sh
bundle install
```

日本語のデータを扱うので、UTF-8 のロケールを設定してください（例: `export LANG=ja_JP.UTF-8`）。
ロケールが未設定のシェルでは `bin/rails runner` に日本語を渡したときにエンコーディングエラーになります。

## 開発時の起動

```sh
bin/rails db:prepare
bin/rails s
```

## 実験環境での起動

実験は `experiment` 環境で行います。開発環境と違い、例外時にルーティング一覧を含むデバッグページを出しません。
データベースはシード投入済みスナップショットの複製を指すので、実行のたびに初期状態から始められます。

```sh
cp db/seed.sqlite3 /tmp/run.sqlite3
EXPERIMENT_DB=/tmp/run.sqlite3 EXPERIMENT_LOG=/tmp/run.jsonl FEATURE_ARCHIVE=1 SECRET_KEY_BASE=x \
  bin/rails s -e experiment -p 3000
```

| 環境変数 | 意味 |
|---|---|
| `EXPERIMENT_DB` | 使用するSQLiteファイル。既定は `storage/experiment.sqlite3` |
| `EXPERIMENT_LOG` | リクエスト記録の出力先（JSONL）。未設定なら記録しない |
| `FEATURE_ARCHIVE` | `1` でアーカイブ操作を有効にする |
| `FEATURE_TITLE_LIMIT` | `1` で ToDo のタイトルを100文字以内に制限する（モデルの検証と、編集フォームの `maxlength`） |
| `FEATURE_DUE` | `1` で ToDo の期限（`due_on`）の表示、編集、JSON の読み書きを有効にし、HTML に今日を描く。`EXPERIMENT_TODAY` が必須（なければ起動時に `abort`） |
| `EXPERIMENT_TODAY` | サーバの「今日」（`YYYY-MM-DD`）。ビュー、期限切れの判定、JSON の `today` がすべてこの値を参照する。未指定なら `Date.current`。`experiment` 環境では、指定があるとサーバの時計もその日の 09:00 起点に合わせる（`lib/experiment_clock.rb`。凍結ではなく時差で、時刻は進み続ける）ので、`created_at` などの書き込み時刻も同じ日になる |
| `API_SITUATED` | `1` で JSON の一覧と詳細に `today`、ToDo に `overdue` を足す |
| `SEED_VARIANT` | スナップショットの生成時のみ。`due` で期限入りの 9 行を投入する |
| `UPDATE_NO_CONTENT` | `1` で JSON の更新（`PATCH /api/lists/{id}`、`PATCH /api/todos/{id}`）の成功応答を 204 にする |
| `OPENAPI_STYLE` | 仕様書の生成時のみ。`terse` で「この操作では変わりません」型の警告文を外す（既定は `full`） |
| `SECRET_KEY_BASE` | 未設定なら `experiment-only-fixed-key` を使う |

CSSとJavaScriptを配信する場合は、先に `bin/rails assets:precompile RAILS_ENV=experiment SECRET_KEY_BASE=x` を実行してください。
エージェントはHTTPレベルで話すので、アセットが無くてもHTMLとJSONの操作はすべて完結します。

### リクエスト記録

`EXPERIMENT_LOG` を設定すると、1リクエストにつき1行のJSONLが追記されます。
`/up` と `/assets/` 以下は記録しません。ボディ本文は記録しません。

```json
{"time":"...","method":"GET","path":"/api/lists","status":200,"request_bytes":0,"response_bytes":460,"accept":"*/*","content_type":null,"response_content_type":"application/json; charset=utf-8","duration_ms":6.9}
```

## 二つの表現

| 操作 | HTML | JSON |
|---|---|---|
| リスト一覧 | `GET /`, `GET /lists` | `GET /api/lists` |
| リスト作成フォーム | `GET /lists/new` | なし |
| リスト作成 | `POST /lists` | `POST /api/lists` |
| リスト詳細 | `GET /lists/:id` | `GET /api/lists/:id` |
| リスト編集フォーム | `GET /lists/:id/edit` | なし |
| リスト名変更 | `PATCH /lists/:id` | `PATCH /api/lists/:id` |
| リスト削除 | `DELETE /lists/:id` | `DELETE /api/lists/:id` |
| ToDo追加 | `POST /lists/:list_id/todos` | `POST /api/lists/:list_id/todos` |
| ToDo詳細 | `GET /todos/:id` | `GET /api/todos/:id` |
| ToDo編集フォーム | `GET /todos/:id/edit` | なし |
| ToDoタイトル変更 | `PATCH /todos/:id` | `PATCH /api/todos/:id` |
| ToDo削除 | `DELETE /todos/:id` | `DELETE /api/todos/:id` |
| 完了 | `POST /todos/:todo_id/completion` | `POST /api/todos/:todo_id/completion` |
| 再開 | `DELETE /todos/:todo_id/completion` | `DELETE /api/todos/:todo_id/completion` |
| アーカイブ | `POST /lists/:list_id/archive` | `POST /api/lists/:list_id/archive` |
| アーカイブ解除 | `DELETE /lists/:list_id/archive` | `DELETE /api/lists/:list_id/archive` |

アーカイブの二つは `FEATURE_ARCHIVE=1` のときだけ存在します。

表現はスコープで固定してあり、`Accept` ヘッダや拡張子では切り替えられません。
`GET /lists` に `Accept: application/json` を付けてもHTMLが返り、`GET /api/lists` に `Accept: text/html` を付けてもJSONが返ります。
`/lists.json` と `/api/lists.html` はどちらも404です。

業務ルールに反したときの422は、コントローラが `{"errors":[...]}` の形で返します。
それ以外の例外（存在しないID、未定義のパス、パラメータの包みが無いなど）は `config.exceptions_app` に置いた
`ExceptionsApp`（`lib/exceptions_app.rb`）が一箇所で組み立てます。元のパスが `/api` 以下ならJSON、
そうでなければRails既定の `public/<status>.html` です。JSON表現のエラー本文は常に `{"errors":[...]}` の形になります。

業務ルールは二つだけで、モデルの `validate` に書いてあります。

- アーカイブ済みのリストにはToDoを追加できない
- 完了済みのToDoはタイトルを変更できない（先に再開する）

HTML表現はRails標準のCSRF保護を有効にしたままです。フォームの `authenticity_token` を読んで送り返す必要があります。
JSON表現はフォームを持たずトークンを得る手段がないので、CSRF検証の対象外にしています。

## 機能フラグ

`FEATURE_ARCHIVE=1` を立てると、アーカイブ状態を変更する操作（ルーティングとボタン）が増えます。
`archived_at` カラム、アーカイブ済みリストへの追加を禁じるバリデーション、一覧の「アーカイブ済み」見出し、
詳細の「アーカイブ済み」表示は、フラグと無関係に常に存在します。

## テスト

```sh
bundle exec rspec
```

アーカイブ操作のrequest specはフラグONのときだけ実行されます。

```sh
FEATURE_ARCHIVE=1 bundle exec rspec
```

## OpenAPI仕様書の再生成

仕様書は手で書かず、request specの実行結果から生成します。生成物を手で直さず、直したいときはrequest specを直してください。

```sh
rm -f doc/openapi-v1.yaml doc/openapi-v2.yaml
FEATURE_ARCHIVE=0 OPENAPI=1 bundle exec rspec spec/requests/api
FEATURE_ARCHIVE=1 OPENAPI=1 bundle exec rspec spec/requests/api
```

ファイル名は `openapi-<line>[-terse][-nocontent][-titlelimit][-due][-situated].yaml` で、`OPENAPI_STYLE`、`UPDATE_NO_CONTENT`、`FEATURE_TITLE_LIMIT`、`FEATURE_DUE`、`API_SITUATED` の指定から決まります。
期限の仕様書は `FEATURE_DUE=1 EXPERIMENT_TODAY=2026-03-04 OPENAPI=1 bundle exec rspec spec/requests/api`（`-due`）と、これに `API_SITUATED=1` を足したもの（`-due-situated`）で生成します。
rspec-openapi は同じステータスの例を後勝ちで記録します。`FEATURE_TITLE_LIMIT=1` の「100文字以内」の一文は、上限を確かめる spec を `openapi: false` で記録から外し、完了済みの 422 の `description` に載せています。

`doc/openapi-v1.yaml` と `doc/openapi-v2.yaml` の差分は、アーカイブ系エンドポイントの追加だけになります。

```sh
diff doc/openapi-v1.yaml doc/openapi-v2.yaml
```

## シードとスナップショットの再生成

シードは決定的です。IDと時刻を固定してあるので、作り直しても同じ内容になります。

```sh
bin/rake experiment:snapshot
```

`db/seed.sqlite3` が書き換わります。このファイルはコミットします。
期限入りのスナップショット `db/seed-due.sqlite3`（s7、s8 用。9 行、今日は 2026-03-04 を想定）は `SEED_VARIANT=due bin/rake experiment:snapshot` で作り直します。

`due_on` 列の追加（マイグレーション `20261010000000`）で `db/seed.sqlite3` は作り直しています。7 行の `id`、`list_id`、`title`、`completed_at`、`created_at`、`updated_at` とリストの 3 行は従来と同じで、`due_on` はすべて null です。

| | SHA-256 |
|---|---|
| 旧 `db/seed.sqlite3`（列追加前） | `46ba264743c15f60c0d0ae107b91d570c3a66b06f7547846427686202cbc5e6c` |
| 新 `db/seed.sqlite3` | `f7eeb161479579a186c436b8281c70d52b0b73acc618ea1e49f878f8d7f32d5f` |
| `db/seed-due.sqlite3` | `1e2dc33121a816cd81e7f168814e5ad4ab7c9c3fc58a8a8beaf2d01747adab9a` |

| id | リスト | 状態 | ToDo |
|---|---|---|---|
| 1 | 仕事 | 現行 | 1 週次ミーティングの準備（未完了）/ 2 経費精算（未完了）/ 3 月次レポート提出（完了済み） |
| 2 | 買い物リスト | 現行 | 4 卵（未完了）/ 5 パン（完了済み） |
| 3 | 2025年の目標 | アーカイブ済み | 6 本を12冊読む（完了済み）/ 7 フルマラソン完走（未完了） |
