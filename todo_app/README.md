# todo_app

Kaigi on Rails 2026 の発表「真のREST 2026」で使う比較実験用のToDoアプリです。
同じコントローラを二つのスコープにマウントし、HotwireのHTMLとJSON APIという二つの表現を、
同じ業務ロジックの上に並べています。

- HTML表現: `/` 以下
- JSON表現: `/api` 以下（`format` は `:json` に固定）

エージェントのハーネスや実行ランナーはこのディレクトリには含まれません。

## 必要なもの

- Ruby 3.4.8（`.ruby-version` を参照）
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

| id | リスト | 状態 | ToDo |
|---|---|---|---|
| 1 | 仕事 | 現行 | 1 週次ミーティングの準備（未完了）/ 2 経費精算（未完了）/ 3 月次レポート提出（完了済み） |
| 2 | 買い物リスト | 現行 | 4 卵（未完了）/ 5 パン（完了済み） |
| 3 | 2025年の目標 | アーカイブ済み | 6 本を12冊読む（完了済み）/ 7 フルマラソン完走（未完了） |
