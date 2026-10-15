# 実装・実行指示書: 別モデルでの追試（`experiment/runs-claude-fable-5-1/`）

この文書は、Claude Code に作業を委ねるための指示書です。前提は `agent-harness-design.md`、`experiment/agent/NOTES.md`、`results-interpretation.md` §6（主張の限界）。設計判断は確定済みで、穴や矛盾を見つけたら自分で埋めずに質問してください。

## 1. 目的

本番のデータセット（`experiment/runs/`、`claude-sonnet-5`、N=10）はモデルが一つで、解釈メモ §6 でそれを限界として挙げている。同じ装置をモデルだけ変えて回し、**差の向きが同じか**と、**危険な誤操作の 0 が保つか**を確かめる。数字の絶対値をモデル間で比べる表は作らない。各モデルの中で HTML と JSON の差を見る。

追試の対象は `claude-fable-5-1`。自作ループ（`bin/run`）と参考実行（`bin/reference-run`、Claude Code の `--model`）の両方。

問いは二つに分かれる。

1. 自作ループ: S3 の無効な書き込みの試行（sonnet-5 で JSON 側 8/10）と S4 の古い仕様書（0/10、正直な失敗）が、モデルを変えたときにどうなるか。特に S4 で `PATCH /lists/{id}` に `archived: true` を送って 200 を見て「完了」と報告する偽の成功や、`POST /lists/{id}/archive` を当てずっぽうに叩く経路が出るか。
2. 参考実行: 「HTTP で叩けると気づかない」「書き込みの手前で確認を求める」が、モデルの性質か Claude Code というハーネスの性質か。sonnet-5 では HTML 側が前提の一行なしで 3/10、ありで 8/10 だった。

## 2. 置き場と凍結

- 本番のデータセット `experiment/runs/` と `experiment/runs-pilot/` は**凍結**。ファイルを一つも変えない（`report.md` の再生成も含む）。タグ `experiment-2026-09-20` はそのまま。
- 追試の記録は `experiment/runs-claude-fable-5-1/` に置く。構造は `runs/` と同じ（`s2/html/<n>/run.json` …、`report.md`、`README.md`）。将来別のモデルを足すときは `runs-<モデルID>/` を増やす。
- 試し打ちは従来どおり `RUNS_DIR=../runs-scratch`。
- 記録はデータセットの一部としてコミットする。選ばずに全部入れる方針は `runs/README.md` と同じ。

`RUNS_DIR` は `Config` と `Report` の両方が読むので、コードの変更なしに `RUNS_DIR=../runs-claude-fable-5-1` で書き分けられる。`Report#write` は `@runs_dir/report.md` に書くので、`report.md` も自動的にその中に入る。

## 3. 守るべき制約

**MUST**

- 変えるのはモデルだけ。`prompts/system.md`、`Loop`、`HttpTool`、`scenarios/*.yml`、`todo_app`、参考実行の条件（`--setting-sources ""`、`--allowedTools`、空の一時ディレクトリ、`~/.claude/CLAUDE.md` なし）はすべて本番と同一。`run.json` の `system_prompt_sha256` と `scenario_sha256` が `runs/` の値と一致することで確認する。
- `run.json` の `response_model` が API の報告値として `claude-fable-5-1`（またはその日付付き ID）になっていることを、全実行で確認する。
- 参考実行の秘匿処理（`Sanitizer`）は従来どおり効いていること。`grep -r "$(whoami)" runs-claude-fable-5-1/` が空。

**MUST NOT**

- モデルに合わせてプロンプトや指示文を直さない。新しいモデルが最終行の「結果: …」の形式を守らず `honest_failure` が増えたとしても、それは結果として記録する（§7）。
- `experiment/runs/` の中に何も書かない。実行前に `RUNS_DIR` を必ず確認する。

## 4. 手順

### 4.0 thinking の扱い（先に実装する）

`claude-fable-5-1` は `thinking: {type: "disabled"}` を拒否する。ドキュメント（platform.claude.com/docs/en/build-with-claude/thinking）に「Thinking can't be turned off on these models」と明記されていて、受け付けるのは `adaptive` だけ。effort（`output_config.effort`）は thinking の頻度と深さを調整するだけで、`none` はなく、`low` にしても消えない。つまり本番（sonnet-5、thinking なし）と同じ条件はこのモデルでは作れない。

決めたこと。

- 追試は `thinking: {type: "adaptive"}`、effort は**指定しない**（このモデルの既定は `high`）。`effort: low` は使わない。effort は応答全体に効き、ドキュメントに「Lower effort levels tend to … Make fewer tool calls」とあるので、測定値であるツール呼び出し数に effort の差が混ざる。
- 追試の目的は各モデルの中で HTML と JSON の差の向きを見ることなので、そのモデルの既定に近い条件で両側を同じ設定で回す。thinking の有無がモデル間の交絡になっていることは、データセットカード（§5）に一文で書く。
- temperature は Fable 5.1 でも既定以外を送ると 400 なので、既存の `temperature_dropped` の経路がそのまま効く。変更不要。

実装。

- `Config` に `thinking` を足す。値は `"disabled"` / `"adaptive"`、既定は従来どおり `"disabled"`。`bin/run` に `--thinking adaptive`、環境変数 `THINKING` でも指定できるようにする。`Loop` は `config.thinking` から `thinking: {type: ...}` を組む。`disabled` が拒否されても temperature のように黙って外さず、**エラーで止める**（何を送ったかが記録から曖昧にならないように）。
- `run.json` に `thinking`（送った値）を記録する。本番の記録には無いキーなので、`Report` の実行条件の表では `nil` を `disabled` と読む。
- thinking を有効にすると応答の `content` に `thinking` ブロックが入り、ツールの往復ではそのブロックを署名付きのまま assistant メッセージとして送り返す必要がある。`Loop` が `response.content` をそのまま `messages` に積んでいれば通る。text と tool_use だけを拾って組み直しているなら直す。`final_message` と `claim` は text ブロックだけから取る。`loop_test.rb` に、`thinking` ブロックを含むスタブ応答で往復が壊れないテストを足す。
- `transcript.jsonl` の `api_call` に thinking の本文がそのまま入り、データセットとして公開される。それでよい（`Sanitizer` の対象ではない）。
- `bin/reference-run`（Claude Code）は CLI 側が thinking を扱うので変更なし。
- sonnet-5 側の経路は一切変えない。`bin/run` を `--thinking` なしで回したときの `run.json` が、`thinking` キーの追加以外は変更前と同じであること。

トークンの列は sonnet-5 と比べられない（出力に thinking が含まれ、入力も前のターンの thinking の扱いで変わる）。§4.3 の並置の表からトークンの列を外し、その旨を節の冒頭に書く。

任意（余力があれば、§4.2 のステップ 2 の前に）: sonnet-5 を `--thinking adaptive` で s3 と s4 だけ N=10 回す。置き場は `experiment/runs-claude-sonnet-5-thinking/`。thinking の有無の効果とモデルの効果を分けるための橋渡しで、50 実行。やった場合はそれも並置の表に加える。

### 4.1 試し打ち（`runs-scratch`）

```
cd experiment/agent
RUNS_DIR=../runs-scratch MODEL=claude-fable-5-1 bin/run --thinking adaptive --scenario s0 --runs 1
RUNS_DIR=../runs-scratch bin/reference-run --model claude-fable-5-1 --scenario s2 --condition html --runs 1
```

確認すること。

- 自作ループ: `thinking: adaptive` で往復が通り、`temperature` は既存の分岐（`temperature_dropped` の記録）で外れるか。それ以外のエラーなら止めて質問する。
- `run.json` に `response_model`、`thinking`、`temperature`（`null` 可）、`claim` が入っている。`transcript.jsonl` の `api_call` に `thinking` ブロックが記録されている。`final_message` の最終行が「結果: 完了 / 実行できませんでした / 不明」のどれかになっているか。なっていなければ、その事実を報告して続行（プロンプトは変えない）。
- 参考実行: Claude Code の `--model claude-fable-5-1` が受け付けられ、`run.json` の `response_model`（`init` の `model`）にそのモデルが入る。受け付けない場合はモデル ID の表記を確認し、分からなければ質問する。
- 両方: `runs/` に変化がない（`git --no-optional-locks status --short experiment/runs` が空）。

### 4.2 本番の順序

`RUNS_DIR=../runs-claude-fable-5-1 MODEL=claude-fable-5-1` を付け、自作ループには `--thinking adaptive` を付けて、次の順に回す。主張に効くものから先に取り、途中で止めても意味のあるデータが残るようにする。

1. 参考実行 s2。`--condition html --runs 10`、`--condition html --hint --runs 10`、`--condition json --runs 3`、`--condition json --hint --runs 3`。本番と同じ N。
2. 自作ループ s3 と s4。`bin/run --scenario s3 --runs 10 --interleave`、`bin/run --scenario s4 --runs 10 --interleave`（条件を指定しないと全条件が回る。s4 は html / json / json_v2 の三つ）。
3. 自作ループ s0、s1、s2。各 `--runs 10 --interleave`。時間か費用が足りなければここは後回しでよいが、やるなら三つとも揃える。

各ステップの後に `RUNS_DIR=../runs-claude-fable-5-1 bin/report` で `report.md` を更新し、判定の内訳を見てから次へ進む。`false_success` か `collateral` が一件でも出たら、その `transcript.jsonl` を読んで何が起きたかを NOTES.md に書く。これは追試の主目的の一つなので、出ても止めない。

`bin/run --all` は使わない。s0〜s4 をまとめて回すと途中の確認ができない。

### 4.3 モデル横断の表

`bin/report` に `--against DIR` を足す（既存の出力は変えない）。指定したとき、`report.md` の末尾に「別のデータセットとの並置」の節を一つ足す。行はシナリオ × 条件、列はデータセットごとに次の四つ。

| 列 | 出し方 |
|---|---|
| 成否 | `success` の数 / N |
| HTTP リクエスト | 中央値（最小〜最大） |
| エラー応答 | 中央値（最小〜最大）と、エラー応答が 1 以上だった実行の数 / N |
| 危険な誤操作 | `false_success` + `collateral` の数 |

トークンの列は置かない（§4.0）。

参考実行も同じ節に、行はシナリオ × 条件 × 前提の一行、列は N・到達・success で並べる。各データセットの見出しは `response_model` の値（複数あれば列挙）。

これは「向きが同じか」を目で見るための表で、モデル間の優劣を言う表ではない。節の冒頭にその一文を書く。実装は `Report` に二つ目の `runs_dir` を読ませるだけで、既存のメソッド（`spread`、`format_cell` の部品）を再利用する。`test/report_test.rb` に、二つの一時ディレクトリを与えて並置の節が出ることと、`--against` なしの出力が変わらないことのテストを足す。

## 5. データセットカード

`experiment/runs-claude-fable-5-1/README.md` を書く。`runs/README.md` に倣い、次を含める。

- 目的（§1 の二つの問い）と、本番との関係。**発表の図4の数字は `runs/` のもの**で、これは追試であること。
- 実行条件の表: 実行日、モデル（`response_model` の値）、temperature の扱い、thinking（`adaptive`、effort は既定）、ツール呼び出しの上限、`todo_app` とハーネスのコミット、Claude Code のバージョン。
- 本番との差はモデルと thinking の有無であること。thinking はこのモデルでは切れないので、モデル間の比較にこの交絡が乗っていること、したがって差の向きだけを見ること。同一性の根拠として `system_prompt_sha256` / `scenario_sha256` の値を書く。
- 件数の表（ステップ 3 を省いた場合はその旨）。

`runs/README.md` は凍結なので触らない。追試への参照は `experiment/agent/README.md` の「記録の置き場」の節と `NOTES.md` に書く。

## 6. NOTES.md に残すこと

日付付きで一節。試し打ちで分かったこと（モデルがパラメータを受け付けたか、最終行の形式を守ったか）、本番の順序と所要時間・費用、`report.md` を見て気づいたこと（特に S3 の試行数、S4 の失敗の種類、参考実行の到達数）、想定外の挙動があれば該当する `run_id`。解釈は書かなくてよい（別途メモにする）。

## 7. 受け入れ確認

1. `bundle exec rake test` が通る（§4.0 と §4.3 のテストを含む）。`bin/run --fake correct --scenario s2` の `run.json` が、`thinking` キーの追加以外は変更前と同じ
2. `experiment/runs/` と `experiment/runs-pilot/` に変更がない: `git --no-optional-locks diff --stat -- experiment/runs experiment/runs-pilot` が空、`git --no-optional-locks status --short` にもこの二つが出ない
3. `runs-claude-fable-5-1/**/run.json` の `response_model` がすべて同じモデルを指し、`thinking` が `adaptive`。`system_prompt_sha256` と `scenario_sha256` が `runs/` の対応する実行と一致する
4. 参考実行の記録に作業ディレクトリ、ホーム、OS ユーザー名が残っていない（`Sanitizer` のプレースホルダに置換されている）
5. `RUNS_DIR=../runs-claude-fable-5-1 bin/report --against ../runs` が通り、並置の節が出る。`bin/report`（引数なし、`RUNS_DIR` なし）は実行しない（`runs/report.md` を書き換えるため）
6. `fake:*` の実行が `runs-claude-fable-5-1/` に混ざっていない
7. コミットは、コード（`bin/report --against`、README、NOTES）を `agent:`、記録を `experiment:` の接頭辞で分ける

## 8. 報告してほしいこと

作業の最後に、次を短く。

- ステップ 1〜3（と任意の sonnet-5 thinking 条件）のうちどこまで回したか、所要時間と費用
- S3 の JSON 側でエラー応答が 1 以上だった実行の数、S4 の各条件の判定の内訳、`false_success` / `collateral` の有無
- 参考実行 html の、前提の一行なし／ありそれぞれの到達数と success 数
- 最終行の形式（「結果: …」）を守らなかった実行があれば、その数

## 9. スコープ外

- OpenAI のモデル（`gpt-6-*`）。`Loop` が anthropic gem に直接書かれているので、プロバイダの抽象が要る。別の指示書にする。
- Codex による参考実行。サンドボックスのネットワーク方針の確認が先。
- プロンプト、指示文、ツール定義、シナリオの変更。
- `runs/README.md` の更新。
