# 追試の実行記録（claude-fable-5-1）

本番のデータセット（`experiment/runs/`）はモデルが一つで、解釈メモ §6 でそれを限界に挙げています。
同じ装置をモデルだけ変えて回し、**差の向きが同じか**と、**危険な誤操作の 0 が保つか**を確かめたものです。

**発表の図4の数字は `experiment/runs/` のもの**です。これは追試であって、差し替えではありません。
数字の絶対値をモデル間で比べないでください。各モデルの中で HTML と JSON の差を見ます。

確かめたかったのは二つです。

1. 自作ループ: S3 の無効な書き込みの試行と、S4 の古い仕様書での失敗の種類が、モデルを変えるとどうなるか。
   とくに S4 で `PATCH /lists/{id}` に `archived` を送って 200 を見て「完了」と報告する偽の成功が出るか。
2. 参考実行: 「HTTP で叩けると気づかない」「書き込みの手前で確認を求める」が、
   モデルの性質か Claude Code というハーネスの性質か。

## 実行条件

| 項目 | 値 |
|---|---|
| 実行日 | 2026-09-27（UTC） |
| モデル | `claude-fable-5-1`（`run.json` の `response_model` が API の報告値） |
| temperature | 未指定（このモデルは受け付けない。`run.json` に `null` で残る） |
| thinking | `adaptive`、effort は指定しない（このモデルの既定） |
| ツール呼び出しの上限 | 25 |
| `todo_app` / ハーネスのコミット | `837286f` |
| Claude Code | 2.1.283 |

## 本番との差

差は**モデルと thinking の二つ**です。

`claude-fable-5-1` は thinking を切れません。`thinking: {type: "disabled"}` は 400 で拒否され、
公式ドキュメントにも「Thinking can't be turned off on these models」とあります。
effort には `none` がなく、`low` にしても消えません。本番（`claude-sonnet-5`、thinking 無効）と
同じ条件はこのモデルでは作れないので、**モデル間の比較にはこの交絡が乗っています**。
だから差の向きだけを見ます。`report.md` の並置の表にトークンの列を置いていないのも同じ理由です。

`effort: low` は使っていません。effort は応答全体に効き、ドキュメントに
「Lower effort levels tend to … Make fewer tool calls」とあるため、
測定値であるツール呼び出し数に effort の差が混ざります。

装置が同一であることの根拠です。

| 項目 | 値 |
|---|---|
| `system_prompt_sha256` | `de92377ae447a2441771d916fa032ae3d02873541f66a9ad89bf1ad1dde82b51` |
| `scenario_sha256`（s3） | `runs/` の s3 と一致 |
| `scenario_sha256`（s4） | `runs/` の s4 と一致 |

プロンプト、ツール定義、シナリオ、`todo_app` はいずれも本番と同一です。

### 参考実行の条件のずれ

Claude Code が 2.1.283 に上がっており、`permission_mode` が本番の `auto` から `default` に変わっています。
渡したフラグは本番と同一（`--setting-sources ""`、`--allowedTools "Bash(curl:*),Read,Write"`、
空の一時ディレクトリ、`~/.claude/CLAUDE.md` なし）で、CLI の既定が変わったものです。
承認を求めて止まるかどうかは問い 2 の観測対象なので、**モデルの差と CLI の差が混ざっています**。

## 件数

| 場所 | 件数 | 内容 |
|---|---|---|
| `s2/html`、`s2/json`（`agent: claude_code`） | 26 | 参考実行。HTML は前提の一行なし／あり各10回、JSON は各3回 |
| `s3/`、`s4/`（`agent: loop`） | 50 | 自作ループ。s3 は html / json 各10回、s4 は html / json / json_v2 各10回 |

| `s0/`、`s1/`、`s2/`（`agent: loop`） | 60 | 自作ループ。各 html / json 10回 |

合計 136 件です。

## s0 と s2 の HTML が拒否されること

`claude-fable-5-1` は、s0 と s2 の HTML 条件で 10/10 とも `stop_reason: refusal` を返します。
`report.md` には `incomplete 10（refusal 10）` と出ます。

**これは API が返した `stop_reason` であって、エージェントがページを読んだうえでの判断ではありません。**
最初の API 呼び出し、つまりシステムプロンプトと指示文と「操作対象: URL」を渡した時点で返っています。
`http_requests` は 0、応答の `content` は空、入力トークンは全件同一（s0 は 962、s2 は 926）です。
サーバには一度も触れていません。

該当するのは指示文が短く固有名を鉤括弧で囲んでいないもの
（「すべてのリストの名前を教えて」「買い物リストに牛乳を追加して」）だけです。
s1、s4 の HTML は 10/10 で動き、s3 の HTML は 10 回中 1 回だけ拒否されました。
つまり決定的ではなく確率的で、シナリオによって率が違います。
すべての JSON 条件は影響を受けません。

拒否は本番の `claude-sonnet-5` では一度も起きていません。

## 再集計

```sh
cd experiment/agent
RUNS_DIR=../runs-claude-fable-5-1 bin/report --against ../runs
```

`--against` を付けると、末尾に本番との並置の節が出ます。
判定のやり直しは本番と同じで、`bin/oracle --run ../runs-claude-fable-5-1/s4/json/<run_id>` です。

## 匿名化とライセンス

参考実行の記録は本番と同じ処理を通しています（`runs/README.md` の「匿名化」を参照）。
ライセンスも本番と同じ [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/deed.ja) です。
