# 予備実行の記録

本番（`runs/`）の条件を固定する前に、2026-09-19 に取った 44 実行の記録です。
本番の集計には入りません。
条件を変えた経緯（`agent/NOTES.md`）の裏づけとして残しています。
モデルは本番と同じ `claude-sonnet-5` です。

## 中身

| 種類 | 件数 | 内容 |
|---|---|---|
| 自作ループ（`agent: loop`） | 17 | 変更前のシステムプロンプトと S1 の指示文で回した 15 件（s0 の N=3、s1〜s4 の N=1）と、変更後に s3 を確かめた 2 件 |
| 参考実行（`agent: claude_code`） | 27 | s2 の参考実行。設定条件が本番と違う 24 件（実行した人の個人設定を含む 12 件、`~/.claude/CLAUDE.md` がある状態の 12 件）と、`setting_sources` を記録する前に取った最初の 3 件（s2 の html） |

プロンプトの変更前後は `run.json` の `system_prompt_sha256` と `scenario_sha256` で、参考実行の設定条件は `setting_sources` と `user_claude_md` で判別できます。
設定条件が違う 24 件の `setting_sources` と `user_claude_md` は、記録を移すときに後から付けたラベルで、実行時に記録された値ではありません。

## `report.md` について

`report.md` は 2026-09-19 に作ったものです。
その後、設定条件が違う参考実行 24 件をこのディレクトリに移しましたが、`report.md` は作り直していません。
そのため参考実行の節は、24 件を移す前の N=3 のままです。
自作ループの節は、今の中身から作り直したものと一致します。

今の中身で作り直すには、`agent/` で次を実行します。
コミット済みの `report.md` を上書きしないように、一時ディレクトリに写してから指してください。

```sh
cp -R ../runs-pilot /tmp/runs-pilot
RUNS_DIR=/tmp/runs-pilot bin/report
```

## ライセンス

この記録は CC BY 4.0 です（ルートの [`LICENSE-DATA`](../LICENSE-DATA)）。
