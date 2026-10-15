# 実装指示書: 比較実験用ToDoアプリ（Hotwire HTML / JSON API）

この文書は、Claude Code に実装を委ねるための指示書です。設計判断はすべて確定済みです。仕様どおりに実装し、仕様に穴や矛盾を見つけた場合は、自分で判断を埋めずに質問してください。

## 1. 背景と目的

Kaigi on Rails 2026 の発表「真のREST 2026」で、同じToDoアプリの二つの表現（HotwireのHTML、JSON API）を同じAIエージェントに操作させ、挙動を比較する。エージェントはHTTPレベルで話す（ブラウザは使わない）。HTML側のエージェントにはルートURLだけを、JSON側のエージェントにはOpenAPI仕様書だけを渡し、レスポンスを読んで次の操作を選ばせる。比較の結果は、HTTPリクエスト数、エラー応答数、消費トークン、誤操作の有無を並べた表として発表で示す。

この指示書で作るのは、その実験の対象となるRailsアプリ本体と、実験装置がアプリに要求する接点（専用環境、リクエスト記録、シードDBのスナップショット）です。エージェント側のハーネス、実行ランナー、結果判定（オラクル）は**この指示書のスコープ外**で、後続の作業になります。

### リポジトリ内の位置

このリポジトリ（`REST-talk-2026`）は発表資料全体を管理している。実験に関わるもの、すなわち後日そのまま公開するものは、すべて `experiment/` の下に置く（公開時は `git subtree split --prefix=experiment` で切り出す想定）。

```
REST-talk-2026/
  proposal-draft.md, todo-app-design.md, ...   # 発表資料（触らない）
  experiment/                                   # 公開する一式
    todo_app/                                   # ← この指示書で作るRailsアプリ
    agent/                                      # ハーネス等（後続。今回は作らない）
    runs/                                       # 実行記録（後続）
```

- Railsアプリは `experiment/todo_app/` に作る。アプリ名は `todo_app`（モジュール名 `TodoApp`）。`todo` としてはならない（モジュール `Todo` が `Todo` モデルと衝突する）。
- `experiment/todo_app/` より上の階層のファイルは読まなくてよいし、変更してはならない。
- Railsのコマンド（`bin/rails`、`bundle exec rspec` など）はすべて `experiment/todo_app/` で実行する。以下の相対パスもこのディレクトリ基準。
- 既存のgitリポジトリの中なので、`rails new` には `--skip-git` を付ける。生成される `.gitignore` は `experiment/todo_app/.gitignore` としてそのまま機能する。

アプリは意図的に単純にする。ユーザー、認証、期限、優先度、並び順、検索、ページネーションはいずれも持たない。奇を衒わない、scaffoldに近いRailsアプリであることが、実験の説得力の一部になる。

## 2. 成果物

1. Rails 8.1 アプリケーション一式（`experiment/todo_app/`、アプリ名 `todo_app`）
2. 同じコントローラを `/`（HTML）と `/api`（JSON）の二つのスコープにマウントしたルーティング
3. Alba によるJSONリソース
4. RSpec の request spec と、そこから rspec-openapi で生成した `doc/openapi-v1.yaml` / `doc/openapi-v2.yaml`
5. 決定的なシードと、シード投入済みSQLiteのスナップショット `db/seed.sqlite3`
6. 実験専用のRails環境 `experiment` と、リクエスト記録ミドルウェア
7. `experiment/todo_app/README.md`（起動方法、二つのスコープ、機能フラグ、スナップショットの再生成手順）
8. §14 の受け入れ確認をすべて通した状態

## 3. 守るべき制約（公平性の原則）

実験の妥当性に直結するため、以下は例外なく守る。

**MUST**

- モデル、バリデーション、業務ルール、シードはHTMLとJSONで完全に共有する。差は `respond_to` の分岐の先、すなわちビューとAlbaリソースにだけ置く。
- JSON側は「Railsの標準」に見える形にする。フラットなデータ、snake_caseのキー、ルートキーなし、`errors.full_messages` ベースの422、テストから生成した仕様書。手で設計した形跡を残さない。
- HTML側はJavaScriptを無効にしても全操作が完結すること。必須のリンクとフォームは初回レスポンスのHTMLに含める。
- エラーメッセージは「何がだめか」と「代わりに何をすればよいか」の両方を含める。
- 業務ルールはモデルの `validate` にだけ書く。コントローラやビューに重複させない。

**MUST NOT**

- JSONレスポンスにリンクやURLを含めない（唯一の例外は、Railsの標準挙動である 201 の `Location` ヘッダ）。
- HTML側の `Location` ヘッダやリンクに `/api/...` を、JSON側の `Location` に `/lists/...` のようなHTML側URLを出さない（表現の漏れ）。
- Turbo Frames の遅延読み込み（`<turbo-frame src>`）や Turbo Streams に依存する画面を作らない。
- request spec のテストデータに、シードと同じ名前（「仕事」「買い物リスト」「牛乳」など）を使わない。rspec-openapi は実際の応答を example として仕様書に埋め込むため、実験データが仕様書経由で漏れる。
- OpenAPI仕様書を手で書いたり、生成後に手で直したりしない（`summary` / `description` は request spec のメタデータとして与える）。
- `experiment` 環境で開発モードの例外ページを出さない（ルーティング一覧が表示され、カタログの漏洩になる）。

## 4. 技術スタック

| 項目 | 選択 | 備考 |
|---|---|---|
| Ruby / Rails | Ruby 3.4系、Rails 8.1系の最新 | `experiment/` で `rails new todo_app --skip-git --skip-solid --skip-kamal --skip-thruster --skip-docker --skip-jbuilder --skip-active-storage --skip-action-mailer --skip-action-mailbox --skip-action-text --skip-action-cable --skip-test` 程度。利用可能なフラグは `rails new --help` で確認し、使えないものは外す。`--skip-git` は必須 |
| DB | SQLite | Rails 8のデフォルト |
| フロント | Hotwire（Turbo Drive のみ）、importmap、Propshaft | Rails 8.1のデフォルト。Stimulusは生成されるが使わない |
| JSON | `alba`（3.x） | 公式ドキュメント: https://github.com/okuramasafumi/alba 、Rails連携: https://github.com/okuramasafumi/alba/blob/main/docs/rails.md |
| テスト | `rspec-rails` | request spec を中心にする |
| OpenAPI | `rspec-openapi` | https://github.com/exoego/rspec-openapi 。`OPENAPI=1 bundle exec rspec` で生成 |
| i18n | `rails-i18n`、`config.i18n.default_locale = :ja` | 画面の文言、エラーメッセージ、シードは日本語。コードの識別子は英語 |

Gemfile に足すのは `alba`、`rails-i18n`、`rspec-rails`（development/test）、`rspec-openapi`（test）、必要なら `sqlite3` の明示のみ。それ以外のgemを足す場合は理由を添えて質問する。

## 5. ドメインモデル

```ruby
# db/schema（マイグレーションで作る）
# lists: id, name:string null:false, archived_at:datetime null:true, timestamps
# todos: id, list_id:references null:false (FK), title:string null:false, completed_at:datetime null:true, timestamps

class List < ApplicationRecord
  has_many :todos, dependent: :destroy
  validates :name, presence: true

  def archived? = archived_at.present?
  def archive!   = update!(archived_at: Time.current)
  def unarchive! = update!(archived_at: nil)
end

class Todo < ApplicationRecord
  belongs_to :list
  validates :title, presence: true
  validate :list_must_not_be_archived, on: :create
  validate :title_frozen_while_completed, on: :update

  def completed? = completed_at.present?
  def complete!  = update!(completed_at: Time.current)
  def reopen!    = update!(completed_at: nil)

  private

  def list_must_not_be_archived
    errors.add(:base, "アーカイブ済みのリストにはToDoを追加できません") if list&.archived?
  end

  def title_frozen_while_completed
    return unless completed? && title_changed?
    errors.add(:base, "完了済みのToDoは編集できません。先に再開してください")
  end
end
```

- 完了とアーカイブは boolean ではなく日時で持つ。判定は `completed?` / `archived?` を通す。
- 業務ルールは上記二つの `validate` がすべて。タイトル変更と完了状態の変更は別URLの別操作なので、一つの更新で両方が変わることはない。
- モデルspecで、二つの業務ルールと `complete!` / `reopen!` / `archive!` / `unarchive!` を確認する。

## 6. ルーティング

同じコントローラを二つのスコープにマウントする。HTMLは `/`、JSONは `/api` 以下で `defaults: { format: :json }` を付ける。`/api` 側には `new` / `edit` を作らない。

```ruby
Rails.application.routes.draw do
  todo_routes = lambda do |api:|
    resources :lists, except: (api ? %i[new edit] : []) do
      resources :todos, only: :create
      if Rails.configuration.x.features.archive
        resource :archive, only: %i[create destroy], module: :lists
      end
    end
    resources :todos, only: (api ? %i[show update destroy] : %i[show edit update destroy]) do
      resource :completion, only: %i[create destroy], module: :todos
    end
  end

  root "lists#index"
  todo_routes.call(api: false)

  scope "/api", as: :api, defaults: { format: :json } do
    todo_routes.call(api: true)
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
```

期待するルート一覧（`bin/rails routes` で照合すること）:

| 操作 | HTML | JSON | コントローラ#アクション |
|---|---|---|---|
| リスト一覧 | `GET /`, `GET /lists` | `GET /api/lists` | `lists#index` |
| リスト作成フォーム | `GET /lists/new` | なし | `lists#new` |
| リスト作成 | `POST /lists` | `POST /api/lists` | `lists#create` |
| リスト詳細（ToDo一覧を含む） | `GET /lists/:id` | `GET /api/lists/:id` | `lists#show` |
| リスト編集フォーム | `GET /lists/:id/edit` | なし | `lists#edit` |
| リスト名変更 | `PATCH /lists/:id` | `PATCH /api/lists/:id` | `lists#update` |
| リスト削除 | `DELETE /lists/:id` | `DELETE /api/lists/:id` | `lists#destroy` |
| ToDo追加 | `POST /lists/:list_id/todos` | `POST /api/lists/:list_id/todos` | `todos#create` |
| ToDo詳細 | `GET /todos/:id` | `GET /api/todos/:id` | `todos#show` |
| ToDo編集フォーム | `GET /todos/:id/edit` | なし | `todos#edit` |
| ToDoタイトル変更 | `PATCH /todos/:id` | `PATCH /api/todos/:id` | `todos#update` |
| ToDo削除 | `DELETE /todos/:id` | `DELETE /api/todos/:id` | `todos#destroy` |
| 完了 | `POST /todos/:todo_id/completion` | `POST /api/todos/:todo_id/completion` | `todos/completions#create` |
| 再開 | `DELETE /todos/:todo_id/completion` | `DELETE /api/todos/:todo_id/completion` | `todos/completions#destroy` |
| アーカイブ（フラグON時のみ） | `POST /lists/:list_id/archive` | `POST /api/lists/:list_id/archive` | `lists/archives#create` |
| アーカイブ解除（フラグON時のみ） | `DELETE /lists/:list_id/archive` | `DELETE /api/lists/:list_id/archive` | `lists/archives#destroy` |

`PATCH /todos/:id` はタイトル変更専用。`PATCH /lists/:id` はリスト名変更専用。完了・再開・アーカイブは boolean パラメータではなく、上記サブリソースの作成・削除で行う。`completed` や `archived` を strong parameters で permit してはならない。

## 7. コントローラ

scaffold の形を保ち、`respond_to` で分岐する。

```ruby
class ApplicationController < ActionController::Base
  rescue_from ActiveRecord::RecordNotFound do
    respond_to do |format|
      format.html { render file: Rails.public_path.join("404.html"), status: :not_found, layout: false }
      format.json { render json: { errors: ["見つかりません"] }, status: :not_found }
    end
  end
end

class TodosController < ApplicationController
  before_action :set_todo, only: %i[show edit update destroy]

  def create
    @list = List.find(params[:list_id])
    @todo = @list.todos.build(todo_params)

    respond_to do |format|
      if @todo.save
        format.html { redirect_to @list, notice: "ToDoを追加しました" }
        format.json { render json: TodoResource.new(@todo), status: :created, location: api_todo_url(@todo) }
      else
        format.html { redirect_to @list, alert: @todo.errors.full_messages.to_sentence }
        format.json { render json: { errors: @todo.errors.full_messages }, status: :unprocessable_content }
      end
    end
  end

  def edit
    redirect_to @todo, alert: "完了済みのToDoは編集できません" if @todo.completed?
  end

  def update
    respond_to do |format|
      if @todo.update(todo_params)
        format.html { redirect_to @todo.list, notice: "ToDoを更新しました" }
        format.json { render json: TodoResource.new(@todo) }
      else
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: { errors: @todo.errors.full_messages }, status: :unprocessable_content }
      end
    end
  end

  def destroy
    list = @todo.list
    @todo.destroy!
    respond_to do |format|
      format.html { redirect_to list, notice: "ToDoを削除しました", status: :see_other }
      format.json { head :no_content }
    end
  end

  private

  def set_todo
    @todo = Todo.find(params[:id])
  end

  def todo_params
    params.expect(todo: [:title])
  end
end
```

- `ListsController` も同じ構造。`index` は現行とアーカイブ済みを分けて取り出す。`show` は `todos` を含めて返す。`create` のJSONは `location: api_list_url(@list)`。
- `Todos::CompletionsController` は `create` で `complete!`、`destroy` で `reopen!` を呼ぶ。`Lists::ArchivesController` は `create` で `archive!`、`destroy` で `unarchive!`。いずれもHTMLは所属先（ToDoならリスト詳細、リストならリスト詳細）へリダイレクト、JSONは更新後のリソースを 200 で返す。
- `location:` はJSON側では必ず `api_*_url` を使う。scaffold の `location: @todo` のままだとHTML側のURLが漏れる。
- 422 のステータスシンボルは `:unprocessable_content` を使う（Railsのバージョンが受け付けない場合のみ `:unprocessable_entity`）。
- `params.expect` が使えるバージョンなので使う。permit するのは `list: [:name]` と `todo: [:title]` だけ。
- HTML側でのバリデーション失敗時、フォームがページ内に埋め込まれている `todos#create` はリスト詳細へ `alert` 付きでリダイレクトし、専用フォームページを持つ `update` / `lists#create` は 422 でフォームを再描画する。

## 8. 表現

### 8.1 HTML（Hotwire）

Turbo Drive のデフォルトのまま、`form_with` と `button_to` だけで組む。すべてのフォームはCSRFトークンを hidden field で持ち、`PATCH` / `DELETE` は `_method` hidden field で表す。これはRailsの標準挙動であり、そのまま残す（エージェントがこれを読んで送り返すコストは、意図して計測に含める）。

レイアウトは Rails 8.1 が生成するもの（`stylesheet_link_tag :app`、`javascript_importmap_tags`、meta各種）をそのまま使う。トークン削減のためにレイアウトを削らない。CSSは scaffold 相当の最小限でよい。

文言（リンク・ボタン・見出し・フラッシュ）は日本語。

**リスト一覧 `/`**
- 見出し「リスト」。現行のリスト名を `GET /lists/:id` へのリンクで並べる。
- 見出し「アーカイブ済み」の下に、アーカイブ済みのリストを同じくリンクで並べる（なければ見出しごと出さない）。
- 「新しいリスト」リンク（`/lists/new`）。

**リスト詳細 `/lists/:id`**
- リスト名。アーカイブ済みなら「アーカイブ済み」の表示。
- 「編集」リンク（`/lists/:id/edit`）、「削除」ボタン（`DELETE /lists/:id`）。
- ToDoを未完了・完了済みの順に並べ、各行に以下を描画する。

| ToDoの状態 | 行に描画するもの |
|---|---|
| 未完了 | タイトル、「完了」ボタン（`POST /todos/:id/completion`）、「編集」リンク（`/todos/:id/edit`）、「削除」ボタン（`DELETE /todos/:id`） |
| 完了済み | タイトル（`<s>` で取り消し線）、「再開」ボタン（`DELETE /todos/:id/completion`）、「削除」ボタン。**編集リンクは描画しない** |

- リストがアーカイブ済みでなければ、末尾に「ToDoを追加」フォーム（`POST /lists/:id/todos`、入力は `todo[title]` 一つだけ）。
- アーカイブ済みなら、フォームの代わりに「このリストはアーカイブ済みです。ToDoは追加できません。」の一文。
- フラグON時: アーカイブ済みでなければ「アーカイブ」ボタン（`POST /lists/:id/archive`）、アーカイブ済みなら「アーカイブを解除」ボタン（`DELETE /lists/:id/archive`）。

**ToDo詳細 `/todos/:id`**
- タイトル、状態（未完了／完了済み）、所属リストへのリンク、状態に応じたボタン（詳細の行と同じ規則）。

**フォームページ** `/lists/new`、`/lists/:id/edit`、`/todos/:id/edit`: scaffold 相当。エラーは `full_messages` を列挙。

### 8.2 JSON（Alba）

```ruby
# app/resources/todo_resource.rb
class TodoResource
  include Alba::Resource
  attributes :id, :list_id, :title
  attribute(:completed) { |todo| todo.completed? }
  attributes :completed_at, :created_at, :updated_at
end

# app/resources/list_resource.rb
class ListResource
  include Alba::Resource
  attributes :id, :name
  attribute(:archived) { |list| list.archived? }
  attributes :archived_at, :created_at, :updated_at
end

# app/resources/list_detail_resource.rb（lists#show 用）
class ListDetailResource < ListResource
  many :todos, resource: TodoResource
end
```

- ルートキーなし、キーは snake_case のまま。`transform_keys` は使わない。
- `GET /api/lists` はアーカイブ済みを含む全リストを `ListResource` で配列として返す。`GET /api/lists/:id` は `ListDetailResource`。
- 成功時のステータス: 作成 201（`Location` 付き）、更新・完了・再開・アーカイブ 200、削除 204。
- 失敗時のボディは常に `{ "errors": ["..."] }`。422（バリデーション）、404（存在しないID）。

## 9. OpenAPI仕様書

- request spec を `spec/requests/api/**` に置き、`/api` 以下の全エンドポイントについて、成功系と、該当するものは 422・404 も通す。
- テストデータは `let` / `create` でその場で作り、名前は「テスト用リスト」「テストToDo」のようにシードと重ならないものにする。
- 各エンドポイントに `summary` と `description` をメタデータで与える。`description` には、そのエンドポイントに関わる業務ルールを一文で書く（例: `PATCH /api/todos/{id}` に「完了済みのToDoは編集できず、422を返します。先に完了を取り消してください」）。これはJSON側への意図的な譲歩なので省かない。
- `servers` は `http://localhost:3000/api`。rspec-openapi の設定で `RSpec::OpenAPI.servers` を指定する。
- 生成は `OPENAPI=1 bundle exec rspec spec/requests/api`。出力先は `RSpec::OpenAPI.path` で制御する。
- 二つのスナップショットをコミットする。

| ファイル | 生成コマンド |
|---|---|
| `doc/openapi-v1.yaml` | `FEATURE_ARCHIVE=0 OPENAPI=1 bundle exec rspec spec/requests/api` |
| `doc/openapi-v2.yaml` | `FEATURE_ARCHIVE=1 OPENAPI=1 bundle exec rspec spec/requests/api` |

- アーカイブ系の request spec はフラグONのときだけ実行されるようにする（`skip` 条件、または spec ファイルの読み込み条件）。
- v1 と v2 の差分が「`/api/lists/{list_id}/archive` の追加」だけであることを `diff` で確認する。
- 生成した仕様書は手で編集しない。生成結果に問題があれば request spec 側を直す。

## 10. 機能フラグ

- `config/application.rb`（または initializer）で `config.x.features.archive = ENV["FEATURE_ARCHIVE"] == "1"`。
- フラグが立つと、ルーティングに `archive` サブリソースが追加され、リスト詳細にボタンが描画される。
- `archived_at` カラムと「アーカイブ済みリストには追加できない」バリデーション、一覧の「アーカイブ済み」見出し、詳細の「アーカイブ済み」表示は、**フラグと無関係に常に存在する**。フラグが制御するのは「アーカイブ状態を変更する操作」だけ。
- ビューでのフラグ参照は `Rails.configuration.x.features.archive` を直接書くのではなく、ヘルパー（例: `archive_feature_enabled?`）を一つ置く。

## 11. シード

`db/seeds.rb` は決定的にする（`created_at` などに `Time.current` を使わず固定時刻を使う）。IDは明示的に指定する。

| id | リスト | 状態 | ToDo（id, タイトル, 状態） |
|---|---|---|---|
| 1 | 仕事 | 現行 | 1「週次ミーティングの準備」未完了 / 2「経費精算」未完了 / 3「月次レポート提出」**完了済み** |
| 2 | 買い物リスト | 現行 | 4「卵」未完了 / 5「パン」完了済み |
| 3 | 2025年の目標 | **アーカイブ済み** | 6「本を12冊読む」完了済み / 7「フルマラソン完走」未完了 |

`db/seed.sqlite3` の作り方（rake タスク `experiment:snapshot` として用意する）:

1. `experiment` 環境で空のDBファイルに `db:schema:load` と `db:seed` を実行
2. できたファイルを `db/seed.sqlite3` にコピー
3. このファイルはコミットする

## 12. 実験環境 `experiment`

`config/environments/experiment.rb` を追加する。`production.rb` をコピーして、次を変える。

- `config.force_ssl = false`、`config.assume_ssl = false`
- `config.consider_all_requests_local = false`（例外時に開発モードのデバッグページを出さない）
- `config.hosts` は制限しない（localhost で動かす）
- `config.log_level = :warn`
- `config.public_file_server.enabled = true`
- `config.middleware.use RequestRecorder`（下記）
- `config/database.yml` の `experiment` は `database: <%= ENV.fetch("EXPERIMENT_DB", "storage/experiment.sqlite3") %>`
- `SECRET_KEY_BASE` は `config/credentials` に依存しない形にする（`config.secret_key_base = ENV.fetch("SECRET_KEY_BASE", "experiment-only-fixed-key")` など。実験専用環境なので固定値でよい）
- `bin/rails s -e experiment -p 3000` で起動でき、`GET /up` が 200 を返す

`RequestRecorder`（`lib/request_recorder.rb`、Rackミドルウェア。環境ファイルは autoload より先に評価されるので、`experiment.rb` の先頭で `require_relative "../../lib/request_recorder"` する）:

- `ENV["EXPERIMENT_LOG"]` が設定されているときだけ記録する（未設定なら素通し）
- 1リクエストにつき1行、JSONL で追記する: `time`（ISO 8601）、`method`、`path`（クエリ含む）、`status`、`request_bytes`（`Content-Length` またはボディ長）、`response_bytes`、`accept`、`content_type`（リクエスト）、`response_content_type`、`duration_ms`
- `/up` と `/assets/` 以下は記録しない
- リクエスト／レスポンスのボディ本文は記録しない（エージェント側で記録する）

## 13. 実装の順序と各段階の完了条件

| 段階 | 作業 | 完了条件 |
|---|---|---|
| 1 | `experiment/` で `rails new todo_app --skip-git ...`、Gemfile、RSpec 導入、`rails-i18n` 設定、`.gitignore` 確認 | `bin/rails s` が起動し、`bundle exec rspec` が空で通る。`git status` で `experiment/todo_app/` 以外に変更がない |
| 2 | モデル、マイグレーション、モデルspec | 二つの業務ルールと状態変更メソッドの spec が通る |
| 3 | ルーティングとコントローラ（HTML分岐を先に） | `bin/rails routes` が §6 の表と一致する |
| 4 | HTMLビュー | ブラウザでJSを無効にして全操作（作成・編集・完了・再開・削除）ができる。完了済みの行に編集リンクがない。アーカイブ済みリストに追加フォームがない |
| 5 | Albaリソース、JSON分岐、`rescue_from` | `curl -H "Accept: application/json"` を使わずに `/api/...` だけで全操作ができる。422/404 のボディが `{"errors":[...]}` |
| 6 | request spec、rspec-openapi 設定、`openapi-v1.yaml` 生成 | 仕様書に全 `/api` エンドポイントと 422/404 が含まれ、example にシードの名前が含まれない |
| 7 | 機能フラグ、アーカイブ機能、`openapi-v2.yaml` 生成 | フラグOFFで `archive` ルートが存在しない。v1/v2 の diff が archive の追加のみ |
| 8 | シード、`experiment:snapshot` | `db/seed.sqlite3` がコミットされ、再生成しても同じ内容になる |
| 9 | `experiment` 環境、`RequestRecorder` | §14 の受け入れ確認がすべて通る |
| 10 | README | 起動、二つのスコープ、フラグ、スナップショット再生成、仕様書再生成の手順が書かれている |

各段階でコミットする。コミットメッセージは英語で簡潔に、先頭に `todo_app:` を付ける（発表資料のコミットと区別するため）。コミットに含めるのは `experiment/todo_app/` 以下のファイルだけ。

## 14. 受け入れ確認

`experiment` 環境で以下を手で通し、結果をREADMEまたはPR説明に貼る（`experiment/todo_app/` で実行）。

```sh
cp db/seed.sqlite3 /tmp/run.sqlite3
EXPERIMENT_DB=/tmp/run.sqlite3 EXPERIMENT_LOG=/tmp/run.jsonl FEATURE_ARCHIVE=1 SECRET_KEY_BASE=x \
  bin/rails s -e experiment -p 3000
```

**HTML側（`curl` のみ、Cookie jar とCSRFトークンの手動転記で）**

1. `GET /` にリスト三つ（うち「2025年の目標」はアーカイブ済み見出しの下）が並び、それぞれが `/lists/:id` へのリンクである
2. `GET /lists/2` に「ToDoを追加」フォームがあり、フォームの `action` が `/lists/2/todos`、hidden に `authenticity_token` がある。`POST /lists/2/todos` に `todo[title]=牛乳` を送ると 302 で `/lists/2` に戻り、「牛乳」が増えている
3. `GET /lists/1` で「月次レポート提出」の行に編集リンクがなく「再開」ボタンがある。`DELETE /todos/3/completion`（`_method=delete`）→ 編集リンクが現れる → `PATCH /todos/3` でタイトル変更 → `POST /todos/3/completion` で再度完了
4. `GET /lists/3` に追加フォームがなく「アーカイブ済み」の説明文がある。それでも `POST /lists/3/todos` を送ると 302 で戻り、alert にバリデーションメッセージが出て、ToDoは増えていない
5. `GET /lists/1` に「アーカイブ」ボタンがあり、`POST /lists/1/archive` で `GET /` の「アーカイブ済み」に「仕事」が移る
6. `GET /todos/3/edit` は（完了済みなら）`/todos/3` へリダイレクトする
7. `GET /lists/999` は本番相当の404ページで、ルーティング一覧を含まない
8. 応答のどこにも `/api/` が現れない（`grep`）

**JSON側**

1. `GET /api/lists` が3件の配列で、`archived` が `2025年の目標` だけ `true`
2. `GET /api/lists/2` に `todos` が埋め込まれている
3. `POST /api/lists/2/todos` に `{"todo":{"title":"牛乳"}}` → 201、`Location: http://localhost:3000/api/todos/8`
4. `PATCH /api/todos/3` に `{"todo":{"title":"x"}}` → 422、`{"errors":["完了済みのToDoは編集できません。先に再開してください"]}`
5. `DELETE /api/todos/3/completion` → 200、`completed: false`。その後 `PATCH /api/todos/3` → 200
6. `POST /api/lists/3/todos` → 422、`{"errors":["アーカイブ済みのリストにはToDoを追加できません"]}`
7. `PATCH /api/lists/1` に `{"list":{"archived":true}}` → 200 だが `archived` は `false` のまま（permit されていないので無視される。この挙動は実験で観測したい対象なので、エラーにしてはならない）
8. `POST /api/lists/1/archive` → 200、`archived: true`
9. `GET /api/lists/999` → 404、`{"errors":["見つかりません"]}`
10. 応答のどこにも `http://localhost:3000/lists` や `/todos/`（`/api/` 抜き）が現れない（`grep`）
11. `Accept: text/html` を付けて `GET /api/lists` を叩いてもJSONが返る

**共通**

1. `/tmp/run.jsonl` に上記の全リクエストが1行ずつ記録され、`/up` は記録されていない
2. `FEATURE_ARCHIVE` を外して再起動すると、`POST /lists/1/archive` と `POST /api/lists/1/archive` が 404 になり、HTMLにボタンが出ない
3. `diff doc/openapi-v1.yaml doc/openapi-v2.yaml` の差分が archive 系エンドポイントの追加だけである
4. `grep -E "仕事|買い物リスト|牛乳|月次レポート" doc/openapi-*.yaml` が何も返さない

## 15. スコープ外（この指示書ではやらない）

- エージェントのハーネス、汎用HTTPツール、実行ランナー、オラクル、集計（後続の `experiment/agent/` で作る。Railsアプリのコードを `require` しない独立したRubyコードになる予定なので、アプリ側から依存を作らない。`experiment/agent/` や `experiment/runs/` のディレクトリを先回りして作る必要もない）
- `experiment/README.md`（公開リポジトリの表紙。後続で書く）
- React などのフロントエンド
- `text/markdown` 表現
- JSONレスポンスへのリンク付与（後日、第三条件として追加する可能性があるため、Albaリソースに条件付き属性を足しやすい構造にしておくのは歓迎するが、v1/v2 では実装しない）
- 認証、ユーザー、デプロイ

## 付録A. 設計判断の要旨（変更しないこと）

| 論点 | 決定 | 理由 |
|---|---|---|
| アプリの数 | 一つ | 二つ作ると業務ロジックの差が混入し、公平性の疑いを構造的に消せない |
| 状態変更のURL | サブリソース（`completion`, `archive`） | 操作ごとにURLが分かれ、HTMLの「描画されるボタン」と仕様書の「存在する操作」が一対一に対応する。動詞URLはRESTの発表で使えない |
| ToDo作成 | `POST /lists/:list_id/todos` | Rails Guides の shallow nesting。リストはページ文脈で決まり、JSON側は名前とIDの対応を自力で解く必要がある |
| 表現の切り替え | `/api` スコープで `format` 固定 | 同一URLのコンテントネゴシエーションだと `Accept` の付け忘れで条件が混ざる |
| JSONシリアライザ | Alba | jbuilder は同梱だが現場での採用実態に疑問 |
| テスト | RSpec + rspec-openapi | 仕様書生成の成熟度 |
| 言語 | 日本語（文言・エラー・シード） | 指示と聴衆が日本語。両表現で同一なので公平性に影響しない |
| 実行環境 | 専用の `experiment` 環境 | 開発モードの例外ページはルーティング一覧を含み、カタログの漏洩になる。本番環境は SSL 強制が邪魔 |
| 置き場所と名前 | 発表資料と同じリポジトリの `experiment/todo_app/`、アプリ名 `todo_app` | 公開する一式を `experiment/` に閉じ込めて後で切り出す。アプリ名は `<title>` や Cookie 名に現れるので、発表用デモとわかる名前ではなく中立的な名前にする。公開リポジトリの名前は切り出し時に決める |

## 付録B. 実験シナリオ（参考。アプリ側の要件を理解するためのもの）

| シナリオ | エージェントへの指示（案） | 期待する終端状態 |
|---|---|---|
| S0 対照 | すべてのリストの名前を教えて | 変更なし |
| S1 完了済みの編集 | 「仕事」の「月次レポート提出」のタイトルを「月次レポート提出（9月分）」に変えて。完了状態はそのままで | todo 3 のタイトル変更、`completed_at` 非nil、他は変更なし。正解経路は 再開 → 編集 → 完了 |
| S2 名前からの追加 | 買い物リストに牛乳を追加して | list 2 に「牛乳」（未完了）が1件追加、他は変更なし |
| S3 アーカイブ済みへの追加 | 「2025年の目標」に「振り返りを書く」を追加して | 変更なし。エージェントが「追加できない」と報告する |
| S4 拡張（フラグONのサーバ） | 「仕事」リストをアーカイブして | list 1 の `archived_at` 非nil、他は変更なし。JSON側は v1 仕様書（古い）と v2 仕様書（対照）の二条件 |

オラクルは実行前後の `lists` / `todos` テーブルを比較し、成功／正直な失敗／偽の成功／巻き添えの四つに分類する。S4 の JSON 側で想定される「偽の成功」は、§14 JSON側 7 の挙動（`archived` を送っても無視されて 200）を完了と誤認するケース。
