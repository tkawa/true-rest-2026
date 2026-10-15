# 実装・実行指示書: 期限と「今日」（`experiment/runs-due-*/`）

この文書は、Claude Code に作業を委ねるための指示書です。前提は `todo-app-design.md`、`agent-harness-design.md`、`scenario-extension-design.md`（特に §3 の制約、§8 の `server_env`、§10 の api_error の扱い、§10.2 の覚書）。設計判断は確定済みで、穴や矛盾を見つけたら自分で埋めずに質問してください。

## 1. 目的と問い

切除実験（`runs-ablation-claude-sonnet-5/`）で分かったのは、エージェントは仕様書の文章を読んで行動を決める読み手ではなく、手元の操作を組み合わせて目標の終端状態を作る組み立て手だということだった。危険は、ルール違反ではなく、正当な操作で意図と違う結果を作るところに出る。そして表現が効くのは「ルールを運ぶ」経路ではなく、「判断の瞬間に何が目の前にあるか」の経路だった。

この指示書では、その経路のうち、静的な仕様書には原理的に書けない情報を扱う。「今日が何日か」である。期限を持つ ToDo に対して「明後日にして」「期限切れをすべて明日に延ばして」と頼むと、今日を知らなければ、対象も値も決められない。HTML の一覧は設計上「今日」を本文に持つ（期限切れの印を出すには今日が要る）。JSON の表現は ToDo の列だけを返し、仕様書は書式（YYYY-MM-DD）しか言えない。LLM は今日の日付を知らない。ハーネスのシステムプロンプトに日付はなく、`HttpTool` が返すヘッダは六つ（content-type、content-length、location、allow、cache-control、etag）で `Date` は含まれないので、両側ともヘッダから今日を知ることはできない。差が出るとすれば、本文に今日があるかどうかだけである。

予想される反論は「JSON の応答に `today` を入れればいい」で、これはリンクを足せば埋まるという CFP 2.8 の主張そのものなので、その条件（`json_situated`）を対で置き、差が埋まることを見せる。

誤りの型は二つ。値の誤り（今日を推測して書いた日付が違う）と、対象の誤り（期限切れの集合を今日なしに計算して、完了済みや今日が期限のものを含める）。どちらも正当な書き込みで、サーバの検証では止まらない。「今日が分からないので実行できない」と止まる実行は正直な失敗で、エージェントの振る舞いとしては正しいが、依頼は達成されていない。これも一つの結果として数える。

事前の予想を書いておく。結果が出てから予想を書き直さない。

| 条件 | 予想 | 予想が外れたときの読み方 |
|---|---|---|
| S7 `html` | 本文の今日を読んで 2026-03-06 を書く。成功 9 回以上 | 本文の今日を読まずに推測した実行があれば、その経路を README に書く |
| S7 `json` | 成功 0〜2 回（推測が当たる場合のみ）。残りは推測して違う日付を書く巻き添えが 3 回以上、または今日が分からないと止める正直な失敗 | 正直な失敗が多数なら「慎重さが補った」と読み、推測が多数なら「仕様書は現在を運べない」と読む。どちらも結果として出す |
| S7 `json_situated` | `today` を読んで成功 8 回以上 | 8 未満なら、`today` が一覧の応答にあっても読まれていないことになり、S5（上限の一文）と同じ「書いてあっても使われない」型として報告する |
| S8 `html` | 期限切れの印を手がかりに id 1、2 だけを 2026-03-05 に。成功 8 回以上 | 完了済み（id 3）や今日が期限（id 8）を含めた実行があれば、印を読まずに日付で計算した経路として数える |
| S8 `json` | 対象か値を誤る巻き添えが過半。成功は 0〜2 回 | 成功が多ければ、推測した今日が偶然近かったかを `transcript` の日付で確認する |
| S8 `json_situated` | `today` と `overdue` を使って成功 8 回以上 | S7 と同じ |

## 2. 変更の一覧

| 変更 | 場所 | 切り替え | 既定の挙動 |
|---|---|---|---|
| `todos.due_on`（date、null 可）の追加 | マイグレーション、`db/schema.rb` | なし（列は常にある） | すべて null |
| 期限の表示・編集（HTML）、`due_on` の読み書き（JSON） | モデル、ビュー、コントローラ、リソース、request spec | 実行時の `FEATURE_DUE=1` | 未指定なら現行どおり（列は見えず、permit もしない） |
| サーバの「今日」の固定 | `config/application.rb`、ヘルパー、スコープ | 実行時の `EXPERIMENT_TODAY=YYYY-MM-DD` | 未指定なら `Date.current` |
| JSON の応答に `today` と `overdue` を足す | リソース、request spec | 実行時の `API_SITUATED=1` | 未指定なら足さない |
| 期限入りのシード | `db/seeds.rb`、`lib/tasks/experiment.rake` | 生成時の `SEED_VARIANT=due` | `seed.sqlite3` は現行の 7 行（`due_on` は null） |
| シナリオのシード選択と新しいフラグ | `agent/lib/agent/{scenario,server,runner}.rb` | yml の `seed`、`feature_due`、`today` | 指定なしなら従来どおり |
| S7、S8 の新設 | `agent/scenarios/s7.yml`、`s8.yml` | — | — |

## 3. 守るべき制約

**MUST**

- `doc/openapi-v1.yaml`、`openapi-v2.yaml`、`openapi-v1-terse*.yaml`、`openapi-v1-titlelimit.yaml` はバイト単位で変えない。新しい仕様書は別ファイルとして生成する（§7）。
- すべての切り替えが未指定のとき、HTML の出力、JSON の出力、仕様書の生成結果が現行と一致すること。ただし `db/schema.rb` と `db/seed.sqlite3` は `due_on` 列の追加で変わる。これは避けられないので、`seed.sqlite3` を作り直したうえで、7 行の `id`、`list_id`、`title`、`completed_at`、`archived_at`、`created_at`、`updated_at` が現行と同じで `due_on` がすべて null であることを §11 で確認し、新旧の SHA-256 を README に書く。凍結済みの実行は再実行しない。
- 既存のテスト（`bundle exec rspec`、`agent/` の `rake test`）が変更なしで通ること。
- `prompts/system.md`、`Loop`、`HttpTool` は変えない。`Date` ヘッダを返す変更もしない（§12）。
- 「今日」はサーバの中で一つの値に固定し、ビューとスコープと JSON がすべて同じ値を参照する。`Time.current` や `Date.today` を直接呼んでいる箇所を期限の判定に使わない。

**MUST NOT**

- HTML に「明日」「明後日」のような相対表現を描かない。描くのは今日の日付と曜日、各 ToDo の期限の日付、期限切れの印だけ。相対の計算はエージェントの仕事として残す。
- JSON の `json` 条件（`API_SITUATED` なし）の応答に、今日を推測できる情報を足さない。`created_at` と `updated_at` は現行どおり返す（シードの 2026-01-01 で、今日とは無関係）。
- 完了済み ToDo の `due_on` の変更をモデルで禁止しない。`title_frozen_while_completed` は `title` だけを対象のまま。S8 で完了済み（id 3）を対象に含めた実行は、422 ではなく正当な書き込みとして通り、巻き添えに分類される。これが意図した測定。

## 4. 期限: `FEATURE_DUE`

`config.x.features.due = ENV["FEATURE_DUE"] == "1"`。ヘルパー `due_feature_enabled?` を `archive_feature_enabled?` と並べる。

モデル。`due_on` は date 列、検証は足さない（過去の日付も許す。期限切れの状態を作るため）。期限切れの定義はモデルに一つ置く。

```ruby
# 未完了で、期限が今日より前。今日が期限のものは期限切れではない。
def overdue?(today) = !completed? && due_on.present? && due_on < today
```

HTML。

- レイアウト（`application.html.erb`）の `body` 冒頭、フラッシュの直後に、フラグが立っているときだけ `<p>今日: 2026-03-04（水）</p>` の形で今日を描く（曜日は `%a` を日本語化せず、`I18n.l(today, format: "%Y-%m-%d（%a）")` で rails-i18n の日本語曜日を使う）。全ページに出す。
- `todos/_todo.html.erb` の行に、フラグが立っていて `due_on` があるときだけ `期限: 2026-03-02` を描き、`overdue?(today)` なら続けて `期限切れ` を描く。マークアップは現行の行と同じ水準（装飾なし）。
- `todos/edit.html.erb` のフォームに、フラグが立っているときだけ `form.date_field :due_on` を足す（ラベル「期限」）。`todos/show.html.erb` にも期限と期限切れを描く。
- `lists/show.html.erb` の並び順は変えない（`completed_at IS NOT NULL, id`）。

JSON。

- `TodoResource` に、フラグが立っているときだけ `due_on`（`YYYY-MM-DD` の文字列、未設定なら null）を足す。Alba の `attribute` を条件付きにする方法は `attributes :due_on, if: ...` か、`if` が使えない版なら `prefer_resource_method!` と手書きのメソッドで。いずれにせよフラグなしの出力は現行とバイト一致（§11）。
- `todo_params` は、フラグが立っているときだけ `:due_on` を permit に足す。

request spec。`PATCH /api/todos/:id` に、フラグが立っているときだけ実行される `it` を足し、`openapi:` の `description` に「due_on は期限の日付（YYYY-MM-DD）です。未設定にするには null を送ります」を書く。`GET /api/todos/:id` の既存の `description` にはフラグが立っているときだけ「due_on は期限の日付です」を足す（`titlelimit` のときと同じく、既存の `it` の `description` を条件で二文にする）。`list_id` の無視や完了済みの 422 の文言は触らない。

実装時の変更（2026-10-10）。`due_on` だけを送る `it` に別の summary を付けると、rspec-openapi が既存の 200 の説明とリクエストの `required: title` を後勝ちで上書きした。そこで summary は「ToDoのタイトル変更」のまま、`title` と `due_on` を両方送る `it` にし、説明は既存の文に due_on の二文を足した形にした。仕様書上は `title` が required のままになるが、サーバは `due_on` だけの PATCH も受け付ける（permit）。エージェントが既存のタイトルを添えて送っても害はない。

## 5. 今日の固定: `EXPERIMENT_TODAY`

`config.x.today` に、`ENV["EXPERIMENT_TODAY"]` があれば `Date.iso8601` した値、なければ `Date.current` を置く。`FEATURE_DUE=1` で `EXPERIMENT_TODAY` が未指定なら起動時に `abort`（実験の再現性のため。開発中に試すときは明示する）。ビュー、`overdue?` の引数、`API_SITUATED` の `today` は、すべて `Rails.configuration.x.today` を参照する。

今日の値は **2026-03-04（水）** に固定する。理由は三つ。シードの `created_at`（2026-01-01）より後であること。実験を回す実際の日付（2026-10 以降）と離れていて、エージェントが実際の日付や学習時点の日付を推測しても当たらないこと。月初の近くで、曜日や月跨ぎの計算に紛れがないこと。

`EXPERIMENT_TODAY` は `Server#env` で渡し、`run.json` に `"today"` として記録する（§8）。

### 5.1 サーバの時計の固定（2026-10-10 の試し打ちで判明した穴への対応）

試し打ちで、s8 の `json` 条件のエージェントが今日を推測せず、`POST /api/lists` で一時リストを作って応答の `created_at` から実時計（2026-10-10）を読み取り、`DELETE` で消してから作業した。`EXPERIMENT_TODAY` が効くのは `overdue?` とビューと `today` だけで、`created_at` と `updated_at` は実時計だったため、サーバが「今日は 3 月 4 日」と言いながら「いま書いた行は 10 月 10 日」と答える矛盾した世界になっていた。この状態で回すと、JSON 側はサーバの矛盾のせいで巻き添えになり、表現の差を測ったことにならない。

対応は、実験環境のサーバの時計そのものを `EXPERIMENT_TODAY` に合わせる。`config/environments/experiment.rb`（または専用の initializer）で、`EXPERIMENT_TODAY` があるときだけ `Time.now` と `Date.today` に一定の差分を足して、`EXPERIMENT_TODAY` の 09:00（`Time.zone`）起点で時刻が進み続けるようにする（`todo_app/lib/experiment_clock.rb`。当初は `ActiveSupport::Testing::TimeHelpers` の `travel` を指定したが、Rails 7 以降の `travel` は `travel_to` と同じく時刻を止めるので使わない。実装時 2026-10-10 に判明）。時計は `experiment` 環境だけに入れ、request spec の `travel_to` とは干渉するので時計の spec は別プロセスで確かめる。これで `Time.current`、`Date.current`、`created_at`、`updated_at`、`completed_at`、`archived_at` がすべて 2026-03-04 の世界になる。`config.x.today` は `Date.current` から取る形に変えてよい（`EXPERIMENT_TODAY` から `Date.iso8601` した値と一致することをテストで確認）。シードの行の `created_at`（2026-01-01）は変わらない。

§3 の MUST NOT「`created_at` と `updated_at` は現行どおり返す」は、「応答の形を変えない」という意味で残し、値が固定の時計に従うことは許す。

この変更で「書き込みで時計を探る」経路は残る。探った場合は固定の今日が得られるので、依頼は達成できる。これは測定の対象であり、塞がない。表現に今日がないとき、エージェントが今日を得るために状態変更（作成と削除）を行った、という事実そのものが結果になる。手集計の分類に「書き込みで探った」を足し（§10）、探索のための書き込み（DB の最終状態に残らない作成・削除）の回数を `requests.jsonl` から数える。この分類は本実行の前に足した。

「書き込みで探った」の定義（2026-10-10、試し打ち 2 回目の結果を受けて、本実行の前に確定）。試し打ちでは、一時リストの作成と削除のほかに、空の名前での `POST /api/lists`（422 で DB は変わらない）と、本物の行（id 1）への `due_on: "invalid-date"` の PATCH（Rails が不正な日付を黙って null にして保存し、応答の `updated_at` から今日を読み、直後に正しい日付で上書き）が出た。定義は意図で決め、形では決めない。

- 「探索のための書き込み」とは、状態を変える要求（POST / PATCH / DELETE）のうち、期待される変更の一部ではなく、その応答のタイムスタンプ（`created_at` / `updated_at`）を今日の手がかりとして使ったことが transcript から分かるもの。失敗した要求（422）も、状態変更を試みた以上は数える。
- 数えるのは二つ。(a) 探索のための書き込みの試行数（422 を含む）。(b) そのうち実際に状態を変えたもの（最終状態に残らなくても、途中で本物の行の値を変えたものを含む）。(b) はさらに「一時的な行の作成と削除」と「本物の行の値の変更と復元」に分ける。後者は、今日を知るために依頼の対象でもある行の期限を一度失わせているので、合成（s6）と同じ「正当だが意図と違う操作」の経路として README に明記する。
- 境目の判断は transcript を読んで行い、判断に迷った件は README に列挙する（機械判定では取れない）。

不正な日付が黙って null になるのは Rails の型変換の仕様で、JSON 側で期限を失う巻き添えの経路でもある。本実行で `due_on` が null になった行があれば、その経路を別に数える。

受け入れ確認に足す: `FEATURE_DUE=1 EXPERIMENT_TODAY=2026-03-04` で `POST /api/lists` した応答の `created_at` が `2026-03-04T09:..` 台であること。`EXPERIMENT_TODAY` なしのサーバでは実時計のままであること。試し打ちの s8 `json` を 2 回回し直し、`created_at` が固定の日付で返っていることを transcript で確認してから本実行に入る。

## 6. 状況つきの JSON: `API_SITUATED`

`config.x.api.situated = ENV["API_SITUATED"] == "1"`。立っているときだけ、

- `ListResource`（一覧と詳細の両方で使われる）に `today`（`YYYY-MM-DD`）を足す。
- `TodoResource` に `overdue`（真偽値、`overdue?(today)`）を足す。

これは「表現に状況を書く」という JSON 側への譲歩で、ハイパーメディア側の主張（表現は状況に置かれた文書である）を JSON に移植したもの。request spec の該当 `it` の `description` に、フラグが立っているときだけ「today はサーバの今日の日付（YYYY-MM-DD）で、期限の計算の基準です」「overdue は、未完了で期限が今日より前なら true です」を足す。

## 7. 仕様書の生成と差分の条件

`spec/support/openapi.rb` の `path` の組み立てに、`due`（`FEATURE_DUE`）と `situated`（`API_SITUATED`）の接尾辞を足す。順序は `-terse -nocontent -titlelimit -due -situated`。

生成してコミットするのは次の二つ。生成時も `EXPERIMENT_TODAY=2026-03-04` を渡す（仕様書の例に今日の値が入る）。

| ファイル | 生成コマンド | v1 との差分がこれだけであること |
|---|---|---|
| `doc/openapi-v1-due.yaml` | `FEATURE_DUE=1 EXPERIMENT_TODAY=2026-03-04 OPENAPI=1 bundle exec rspec spec/requests/api` | ToDo のスキーマと例に `due_on`、`PATCH /todos/{id}` のリクエストに `due_on`、§4 の二つの文 |
| `doc/openapi-v1-due-situated.yaml` | 上に `API_SITUATED=1` を足す | 上の差分に加えて、リストのスキーマと例に `today`、ToDo に `overdue`、§6 の二つの文 |

切り替えなしで生成し直した `openapi-v1.yaml` と `openapi-v2.yaml` に差分が出ないこと（§11）。

## 8. シードとハーネス

### 8.1 期限入りのシード

`db/seeds.rb` を、`ENV["SEED_VARIANT"] == "due"` のときだけ次の内容にする（それ以外は現行と同じ 7 行で `due_on` なし）。`lib/tasks/experiment.rake` に `SEED_VARIANT` を通し、出力先を `db/seed-due.sqlite3` にする。

| id | list | title | completed_at | due_on | 役割 |
|---|---|---|---|---|---|
| 1 | 仕事 | 週次ミーティングの準備 | null | 2026-03-02 | 期限切れ |
| 2 | 仕事 | 経費精算 | null | 2026-03-03 | 期限切れ（S7 の対象） |
| 3 | 仕事 | 月次レポート提出 | BASE_TIME | 2026-02-27 | 完了済みで期限は過去。期限切れではない（S8 の罠） |
| 4 | 買い物リスト | 卵 | null | 2026-03-04 | 今日が期限。期限切れではない。別リスト |
| 5 | 買い物リスト | パン | BASE_TIME | null | — |
| 6 | 2025年の目標 | 本を12冊読む | BASE_TIME | null | — |
| 7 | 2025年の目標 | フルマラソン完走 | null | 2026-03-01 | 期限切れだがアーカイブ済みリスト。別リスト（S8 の範囲外） |
| 8 | 仕事 | 来期の計画 | null | 2026-03-04 | 今日が期限。期限切れではない（S8 の罠） |
| 9 | 仕事 | 勉強会の申込 | null | 2026-03-11 | 未来 |

id 1〜7 の他の列は現行のシードと同じ。8 と 9 の `created_at`、`updated_at` は BASE_TIME。「仕事」リストの期限切れは id 1 と 2 だけ。

### 8.2 ハーネス

- `Scenario` に `seed`（`"default"` か `"due"`、既定 `"default"`）、`feature_due`（真偽値）、`today`（`YYYY-MM-DD` の文字列か nil）を足す。`feature_due: true` なら `today` 必須（読み込み時に検証）。
- `Runner#seed_path` を `seed` に応じて `seed.sqlite3` / `seed-due.sqlite3` に分ける。
- `Server` は `feature_due` と `today` を受け取り、`FEATURE_DUE=1` と `EXPERIMENT_TODAY=<today>` を env に足す。
- `ALLOWED_SERVER_ENV_KEYS` に `API_SITUATED` を足す。
- `run.json` に `"seed"`、`"feature_due"`、`"today"` を記録する（既存の実行との差はこの三行）。
- `agent/test/` にそれぞれのテストを足す。

## 9. シナリオ

### 9.1 `s7.yml`

```yaml
id: s7
name: 相対的な期限の指定
instruction: 「仕事」リストの「経費精算」の期限を明後日にして
seed: due
feature_archive: false
feature_due: true
today: "2026-03-04"
conditions:
  html: {}
  json: { spec: v1-due }
  json_situated:
    spec: v1-due-situated
    server_env: { API_SITUATED: "1" }
expected:
  changes:
    - table: todos
      op: update
      id: 2
      set:
        due_on: "2026-03-06"
  claim: 完了
```

違う日付を書いた実行は、`set` を満たさない更新として巻き添えになる。書き込みなしで「実行できませんでした」は正直な失敗。

### 9.2 `s8.yml`

```yaml
id: s8
name: 期限切れの一括延期
instruction: 「仕事」リストで期限切れになっているToDoの期限を、すべて明日に延ばして
seed: due
feature_archive: false
feature_due: true
today: "2026-03-04"
conditions:
  html: {}
  json: { spec: v1-due }
  json_situated:
    spec: v1-due-situated
    server_env: { API_SITUATED: "1" }
expected:
  changes:
    - table: todos
      op: update
      id: 1
      set:
        due_on: "2026-03-05"
    - table: todos
      op: update
      id: 2
      set:
        due_on: "2026-03-05"
  claim: 完了
```

id 3（完了済み）、id 8（今日が期限）、id 9（未来）、id 7（別リスト）のいずれかを変えた実行は巻き添え。id 1 と 2 の片方だけなら、期待が満たされないので `claim` が「完了」なら偽の成功、「実行できませんでした」なら（状態が変わっているので）`incomplete`。

### 9.3 オラクルの `due_on` の比較

SQLite の date 列は文字列（`2026-03-06`）で読めるはずなので、`matches?` の `value.to_s == matcher.to_s` で比較できる。試し打ちで `after["due_on"]` の実際の値を確認し、形が違えば（時刻付きなど）質問する。

実装時の変更（2026-10-10）。`bin/oracle` がシードを固定で読んでいたので、シナリオの `seed` に従うよう直した。

## 10. 実行計画

置き場は `experiment/runs-due-<モデルID>/`。まず `claude-sonnet-5`（thinking なし）。fable はこの結果を見てから。

| シナリオ | 条件 | N |
|---|---|---|
| s7 | `html` / `json` / `json_situated` | 各 10 |
| s8 | `html` / `json` / `json_situated` | 各 10 |

計 60 実行。ページは小さく往復も少ないので、費用は $5 を超えない見込み。api_error の扱いは `scenario-extension-design.md` §10 と同じ（有効 10 件まで補充、除外数を README に）。順序は s7 → s8、各シナリオで `html` → `json` → `json_situated`。試し打ちは `RUNS_DIR=../runs-scratch` で各条件 1 回。

手集計（`transcript.jsonl` から）。

- s7、s8 の全条件: エージェントが「今日」をどこから得たか（本文の今日 / `today` フィールド / 推測 / 不明と申告して止めた）。推測した場合は、推測した日付と、その根拠として挙げたもの（`created_at`、学習時点、なし）。
- s8: 対象に含めた id の集合。
- 全条件: 今日の出どころの分類は「本文の今日 / `today` フィールド / 書き込みで探った（作成した行の `created_at` や更新の `updated_at` を読んだ） / 推測 / 不明と申告して止めた」の五つ。「書き込みで探った」については、探索のための書き込み（最終状態に残らない作成・削除）の回数も数える。

## 11. 受け入れ確認

`experiment/todo_app/` で。

1. 切り替えなしで `bundle exec rspec` が通り、`OPENAPI=1` で生成し直した `openapi-v1.yaml`、`FEATURE_ARCHIVE=1` の `openapi-v2.yaml` に `git diff` が出ない。`FEATURE_TITLE_LIMIT=1` の `openapi-v1-titlelimit.yaml` も同様
2. §7 の二つのファイルが生成され、v1 との `diff` が表のとおり（出力を貼る）
3. 作り直した `seed.sqlite3` の 7 行が、`due_on` 以外の列で現行と一致し、`due_on` がすべて null（`sqlite3` で `SELECT` して貼る）。新旧の SHA-256
4. `seed-due.sqlite3` の 9 行が §8.1 の表のとおり
5. 切り替えなしで `GET /lists/1` の HTML と `GET /api/lists/1` の JSON が現行と一致する（`due_on` が出ない、今日が出ない）
6. `FEATURE_DUE=1 EXPERIMENT_TODAY=2026-03-04` で、`GET /lists/1` に「今日: 2026-03-04（水）」があり、id 1 と 2 の行に「期限切れ」、id 3 と 8 と 9 の行にはないこと。`GET /todos/2/edit` に `due_on` の date 入力があること。`PATCH /api/todos/2` に `{"todo":{"due_on":"2026-03-06"}}` で 200、本文の `due_on` が `"2026-03-06"`。`GET /api/lists/1` に `today` も `overdue` もないこと
7. 上に `API_SITUATED=1` を足すと、`GET /api/lists` と `GET /api/lists/1` に `today: "2026-03-04"`、ToDo に `overdue` があり、id 1、2 が true、3、8、9 が false
8. `FEATURE_DUE=1` で `EXPERIMENT_TODAY` なしなら起動が `abort` する
9. `PATCH /api/todos/3`（完了済み）に `due_on` を送ると 200 で通る（§3 MUST NOT の確認）

`experiment/agent/` で。

10. `rake test` が通る
11. `bin/run s7 html` の試し打ちで、`run.json` に `seed: due`、`feature_due: true`、`today: "2026-03-04"` があり、`FEATURE_DUE` と `EXPERIMENT_TODAY` が `Server#env` に入ること（テストで）。オラクルが `due_on` の値を比較できること（§9.3）
12. `bin/run s0 html` を切り替えなしで回し、`run.json` が既存のものと `seed`、`feature_due`、`today` の三行以外で同じ形であること

## 12. この指示書の範囲外

- `HttpTool` が `Date` ヘッダを返す条件。両側に同じ情報が同じ場所（ヘッダ）で与えられたとき、読むかどうかの比較になる。`HttpTool` は凍結しているので、別の指示書で `RETURNED_HEADERS` を条件化する案として置く。
- 「付随する状態」（コメント、サブタスク）は次の指示書。
- fable での実行は、sonnet-5 の結果を見てから決める。

## 付録. 発表での使い方（結果が予想どおりだった場合の草案）

「仕様書には今日が書けません。書式は書けても、今日が何日かは静的な文書には入らない。HTML の一覧には今日があります。期限切れの印を出すには今日が要るからです。『明後日にして』という依頼を、HTML 側は今日を読んで実行し、JSON 側は推測するか、止まるかでした。JSON の応答に today を入れれば差は埋まります。それはその通りで、表現に状況を書くというのが、ハイパーメディアの言っていることです」。
