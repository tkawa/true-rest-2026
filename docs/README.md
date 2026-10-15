# 設計書

このディレクトリの設計書は、`todo_app/` と `agent/` の実装と、各データセットの実行を Claude Code に委ねるために書いた指示書です。
元のリポジトリのルートにあったものを、中身を書き換えずにコピーしています。

| 文書 | 内容 | 対応するもの |
|---|---|---|
| [`todo-app-design.md`](todo-app-design.md) | 実験対象の ToDo アプリ | `todo_app/` |
| [`agent-harness-design.md`](agent-harness-design.md) | 計測の装置（ループ、ツール、ランナー、判定、集計） | `agent/`、`runs/` |
| [`agent-adhoc-entry-design.md`](agent-adhoc-entry-design.md) | 任意のアプリに向ける入口（`bin/agent`） | `agent/bin/agent` |
| [`agent-model-replication-design.md`](agent-model-replication-design.md) | 別モデルでの追試 | `runs-claude-fable-5-1/`、`runs-claude-sonnet-5-cli-2.1.283/` |
| [`scenario-extension-design.md`](scenario-extension-design.md) | 切除実験（s4〜s6） | `runs-ablation-claude-sonnet-5/` |
| [`due-date-design.md`](due-date-design.md) | 期限と「今日」（s7、s8） | `runs-due-claude-sonnet-5/` |
| [`attached-state-design.md`](attached-state-design.md) | 付随する状態（s9、s10） | `runs-attached-claude-sonnet-5/` |

[`commit-map.tsv`](commit-map.tsv) は、元のリポジトリとこのリポジトリのコミットの対応表です。使い方はルートの README にあります。

## 読むときの注意

文中のパスは、切り出す前の配置（`experiment/todo_app/`、`experiment/runs/` のように `experiment/` が付いた形）で書かれています。
このリポジトリでは `experiment/` を外して読んでください。

公開していない文書への言及が残っています。
解釈メモ（`results-interpretation.md`）、スライドのソース、設計書へのレビュー文書は、このリポジトリに入っていません。

`todo-app-design.md` 以外の 6 本は、実行の時点では版管理していませんでした。
そのため、予想を書いた 3 本（`scenario-extension-design.md`、`due-date-design.md`、`attached-state-design.md`）の §1 が結果を見る前に書かれたことは、このリポジトリ上では検証できません。
