# 実験記録（データセット）

Kaigi on Rails 2026 の発表「真のREST 2026」で示す比較実験の、実行記録そのものです。
発表の表の数字はすべてここから出ています。手元で再集計・再判定できます。

選んで入れているのではなく、**取った実行をすべて**入れています。
都合のよい実行だけを残した疑いが構造的に立たないようにするためです。

## 中身

| 場所 | 件数 | 内容 |
|---|---|---|
| `runs/` | 110 | 本番。自作ループ、シナリオ5本 × 条件2〜3、各 N=10 |
| `runs/s2/` のうち `agent: claude_code` | 26 | 参考実行（Claude Code）。HTML は前提の一行なし／あり各10回、JSON は各3回 |
| `runs-pilot/` | 44 | 予備実行。**古いシステムプロンプトと古い S1 指示文**、および**設定条件が違う参考実行**24件 |

`runs-pilot/` は本番の集計に入りません。条件を変えた経緯（`agent/NOTES.md`）の
裏づけとして残してあります。プロンプトの変更前後は `run.json` の `system_prompt_sha256` と
`scenario_sha256` で、参考実行の設定条件は `setting_sources` で判別できます。
`runs-pilot/` にある参考実行は実行した人の個人設定（出力スタイル、プラグイン、スキル）を
含んだもので、`setting_sources` のラベルは記録を移すときに後から付けました。

## 実行条件

| 項目 | 値 |
|---|---|
| 実行日 | 2026-09-19（UTC） |
| モデル | `claude-sonnet-5`（`run.json` の `response_model` が API の報告値） |
| temperature | 未指定（このモデルは受け付けない。`run.json` に `null` で残る） |
| extended thinking | 無効（`thinking: {type: "disabled"}`） |
| ツール呼び出しの上限 | 25 |
| `todo_app` / ハーネスのコミット | `cd95754` |
| Claude Code | 2.1.275 |

## 参考実行の条件

聴講者が再現できる条件に固定しています。実行した人の個人設定は読み込みません。

| 項目 | 値 |
|---|---|
| 設定の出どころ | `--setting-sources ""`（`plugins` は空、`output_style` は既定） |
| `~/.claude/CLAUDE.md` | なし |
| 許可するツール | `--allowedTools "Bash(curl:*),Read,Write"` |
| システムプロンプト | 変更しない |
| 作業ディレクトリ | 空の一時ディレクトリ（JSON条件のみ `openapi.yaml` を置く） |

条件は `run.json` の `setting_sources`、`user_claude_md`、`allowed_tools`、`available_tools`、
`permission_mode`、`api_key_source` から読めます。
`runs-pilot/` にある参考実行は、条件を固定するまでの経緯として残したもので、
個人設定を含む12件と `~/.claude/CLAUDE.md` がある状態の12件です。
どちらもラベルは記録を移すときに後から付けました。

## 1実行あたりのファイル

| ファイル | 内容 |
|---|---|
| `run.json` | 計測値と判定。表の数字はここから |
| `transcript.jsonl` | API呼び出しごとの送信メッセージ全体と応答、ツール呼び出しの入力と結果 |
| `requests.jsonl` | サーバ側の記録。HTTPリクエスト数とエラー応答数はここから取る |
| `db.sqlite3` | 実行後のDB。判定を再実行できる |
| `server.log` | サーバの標準出力・標準エラー |
| `initial_message.md` | 実際に送った最初のユーザーメッセージ |

## 再集計と再判定

`agent/` で実行します。

```sh
bin/report                                  # runs/ から report.md を作り直す
RUNS_DIR=../runs-pilot bin/report           # 予備実行の集計
bin/oracle --run ../runs/s1/html/<run_id>   # 1実行の判定をやり直す
```

判定はシードDB（`todo_app/db/seed.sqlite3`）と各実行の `db.sqlite3` の差分から出ます。
アプリを動かさなくても再判定できます。

## 匿名化

参考実行（`agent: claude_code`）の `transcript.jsonl` には、Claude Code の stream-json 出力が
入ります。その `system` イベントには実行した人の環境が含まれるため、次の処理を施しています。

- `system` イベントは、実験条件として意味のある項目だけを残す。
  残すのは `type`、`subtype`、`model`、`permissionMode`、`apiKeySource`、`tools`、`claude_code_version`
- 落とした項目: `cwd`、`session_id`、`slash_commands`、`terminal_slash_commands`、`skills`、`agents`、
  `plugins`（社内プラグインの名前・バージョン・パス）、`output_style`、`memory_paths`、
  `messaging_socket_path`、`mcp_servers`、`capabilities`、`uuid`、`analytics_disabled`、
  `product_feedback_disabled`、`fast_mode_state`、`fast_mode_disabled_reason`
- 本文に残るパスは置換する。ホームディレクトリは `<HOME>`、作業ディレクトリは `<WORKDIR>`、
  ソケットのパスは `<SOCKET>`
- OS の利用者名は `<USER>` に置換する。`ls -la` の所有者欄のように、パスの外にも現れるため。
  単語境界でのみ置換するので、トークンの中に同じ並びがあっても壊さない

記録時の処理は `lib/agent/reference/sanitizer.rb` にあります。
規則を足す前に取った記録には `script/sanitize-reference-records` を当てています。
このスクリプトは冪等で、何度当てても結果は同じです。
匿名化しても `run.json` の値と集計結果は変わりません（`response_model`、`permission_mode`、
`api_key_source`、`available_tools` は残す項目から取っています）。

APIキーは記録のどこにも含まれません。

## ライセンス

この実験記録は [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/deed.ja) で公開します。
出典として、この発表とリポジトリを示してください。
コード（`todo_app/` と `agent/`）のライセンスは別に定めます。
