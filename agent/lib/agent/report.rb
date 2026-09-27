require "json"
require "time"

module Agent
  # runs/**/run.json を集めて発表用の表を書く。数値は中央値（最小〜最大）で示す。
  class Report
    RUNS_DIR = File.expand_path("../../../runs", __dir__).freeze
    VERDICTS = %w[success honest_failure false_success collateral incomplete].freeze
    # 参考実行は素のシステムプロンプトで動かすので「結果: …」の行が付かない。
    # 自己申告を読まず、DB差分だけで判定する。
    REFERENCE_VERDICTS = %w[success no_change collateral].freeze
    CONDITION_ORDER = %w[html json json_v2].freeze

    def initialize(runs_dir: ENV.fetch("RUNS_DIR", RUNS_DIR), include_fake: false, against: nil)
      @runs_dir = runs_dir
      @include_fake = include_fake
      @against = against
      @runs = load_runs(@runs_dir)
    end

    def call
      loop_runs, reference_runs = @runs.partition { |run| run["agent"].to_s != "claude_code" }
      [
        "# 実験結果",
        "",
        summary_section(loop_runs),
        matrix_section(loop_runs),
        reference_section(reference_runs),
        comparison_section,
        listing_section(@runs)
      ].compact.join("\n")
    end

    def write(path = File.join(@runs_dir, "report.md"))
      File.write(path, call)
      path
    end

    def run_count = @runs.size

    private

    # 疑似エージェントの実行は装置の確認用なので、既定では表に混ぜない。
    def load_runs(dir)
      runs = Dir.glob(File.join(dir, "**", "run.json")).sort.map { |path| JSON.parse(File.read(path)) }
      @include_fake ? runs : runs.reject { |run| run["agent"].to_s.start_with?("fake:") }
    end

    def summary_section(runs)
      return "実行記録がありません。\n" if runs.empty?

      models = runs.map { |r| r["response_model"] || r["model"] }.uniq.compact
      commits = runs.map { |r| r["todo_app_git_commit"].to_s[0, 7] }.uniq.reject(&:empty?)
      dates = runs.map { |r| r["started_at"].to_s[0, 10] }.uniq.sort
      <<~SECTION
        ## 実行条件

        | 項目 | 値 |
        |---|---|
        | モデル | #{models.join(", ")} |
        | temperature | #{temperatures(runs)} |
        | thinking | #{thinkings(runs)} |
        | ツール呼び出しの上限 | #{runs.map { |r| r["max_tool_calls"] }.uniq.join(", ")} |
        | todo_app のコミット | #{commits.join(", ")} |
        | 実行日 | #{dates.join(" 〜 ")} |
        | 実行数 | #{runs.size} |

      SECTION
    end

    # 新しいモデルは temperature を受け付けないので、送らなかったことを明示する。
    def temperatures(runs)
      runs.map { |run| run["temperature"].nil? ? "未指定（モデルが受け付けない）" : run["temperature"] }
          .uniq.join(", ")
    end

    # incomplete は、ツール上限・時間切れ・APIエラーと、モデル側の拒否が混ざる。
    # 拒否は最初のAPI呼び出しで返ることがあり、打ち切りとは別の現象なので数を分けて出す。
    def verdict_breakdown(cell)
      VERDICTS.filter_map do |verdict|
        runs = cell.select { |run| run["verdict"] == verdict }
        next if runs.empty?

        label = "#{verdict} #{runs.size}"
        refusals = runs.count { |run| run["finish_reason"] == "refusal" }
        refusals.positive? ? "#{label}（refusal #{refusals}）" : label
      end.join(", ")
    end

    # 本番の記録にはこのキーが無い。無い場合は disabled で回している。
    def thinkings(runs)
      runs.map { |run| run["thinking"] || "disabled" }.uniq.join(", ")
    end

    def matrix_section(runs)
      return nil if runs.empty?

      rows = runs.group_by { |run| [ run["scenario"], run["condition"] ] }
      scenarios = runs.map { |run| run["scenario"] }.uniq.sort
      conditions = runs.map { |run| run["condition"] }.uniq
                       .sort_by { |name| CONDITION_ORDER.index(name) || CONDITION_ORDER.size }

      lines = [ "## シナリオ × 条件", "" ]
      lines << "| シナリオ | 条件 | N | 判定の内訳 | HTTPリクエスト | エラー応答 | 入力トークン | 出力トークン | ツール呼び出し | 条件違反 |"
      lines << "|---|---|---|---|---|---|---|---|---|---|"
      scenarios.each do |scenario|
        conditions.each do |condition|
          cell = rows[[ scenario, condition ]]
          next if cell.nil?

          lines << format_cell(scenario, condition, cell)
        end
      end
      lines << ""
      lines.join("\n")
    end

    def format_cell(scenario, condition, cell)
      breakdown = verdict_breakdown(cell)

      [
        "", scenario, condition, cell.size, breakdown,
        spread(cell, "http_requests"), spread(cell, "error_responses"),
        spread(cell, "input_tokens"), spread(cell, "output_tokens"), spread(cell, "tool_calls"),
        cell.count { |run| run["protocol_violation"] }, ""
      ].join(" | ").strip
    end

    def reference_section(runs)
      return nil if runs.empty?

      lines = [
        "## 参考実行（Claude Code）",
        "",
        "判定はDB差分だけで出しています（既製品のシステムプロンプトのままでは自己申告の行が付かないため）。",
        "「到達」は、サーバに1回以上リクエストが届いた実行の数です。",
        "N − 到達 が「到達しなかった」、到達 − success が「到達したが状態変更の手前で止まった」になります。",
        "「前提の一行」は、初期メッセージに「このサービスには HTTP でアクセスできます。」を足したかどうかです。",
        "#{setting_sources_note(runs)}",
        "#{claude_md_note(runs)}",
        "上の表と直接比べられるのは、サーバ側のHTTPリクエスト数だけです。",
        "ツール呼び出しの数え方が両者で異なります（自作ループは `http_request` の回数、",
        "こちらは CLI が使った全ツールの回数）。",
        ""
      ]
      lines << "| シナリオ | 条件 | 前提の一行 | N | 到達 | 判定の内訳 | HTTPリクエスト | エラー応答 | ツール呼び出し | ツールの内訳 | ターン数 | バージョン |"
      lines << "|---|---|---|---|---|---|---|---|---|---|---|---|"
      grouped = runs.group_by { |run| [ run["scenario"], run["condition"], run["hint"] ? 1 : 0 ] }
      grouped.sort_by(&:first).each do |(scenario, condition, hint), cell|
        breakdown = REFERENCE_VERDICTS.filter_map do |verdict|
          count = cell.count { |run| reference_verdict(run) == verdict }
          "#{verdict} #{count}" if count.positive?
        end.join(", ")
        lines << [
          "", scenario, condition, hint.zero? ? "なし" : "あり", cell.size, reached(cell), breakdown,
          spread(cell, "http_requests"), spread(cell, "error_responses"), spread(cell, "tool_calls"),
          tool_breakdown(cell), spread(cell, "num_turns"),
          cell.map { |run| run["claude_code_version"] }.uniq.join(", "), ""
        ].join(" | ").strip
      end
      lines << ""
      lines.join("\n")
    end

    # 既製品の条件。読み込んだ設定の出どころを明示する。
    def setting_sources_note(runs)
      values = runs.map { |run| run["setting_sources"] }.uniq
      return "設定の出どころ: 記録なし。" if values == [ nil ]

      shown = values.map { |v| v.nil? ? "記録なし" : (v.empty? ? "なし（既製品のまま）" : v) }
      "設定の出どころ（`--setting-sources`）: #{shown.join(' / ')}。"
    end

    # ~/.claude/CLAUDE.md は --setting-sources と別に読み込まれる可能性がある。
    def claude_md_note(runs)
      values = runs.map { |run| run["user_claude_md"] }.uniq
      return "~/.claude/CLAUDE.md の有無: 記録なし。" if values == [ nil ]

      shown = values.map { |v| v.nil? ? "記録なし" : (v ? "あり" : "なし") }
      "~/.claude/CLAUDE.md: #{shown.join(' / ')}。"
    end

    # サーバに1回でも届いたか。届かなかった失敗と、届いたうえで止まった失敗を分ける。
    def reached(cell) = cell.count { |run| run["http_requests"].to_i.positive? }

    # 期待する変更が入ったか、巻き添えがあったか。この二つだけで決める。
    def reference_verdict(run)
      return "collateral" if (run["unexpected_changes"] || []).any?
      return "success" if run["expected_changes_satisfied"]

      "no_change"
    end

    # 既製エージェントがどのツールを何回使ったか。自作ループの tool_calls と並べて読む。
    def tool_breakdown(cell)
      tally = Hash.new(0)
      cell.each { |run| (run["tool_calls_by_name"] || {}).each { |name, count| tally[name] += count } }
      return "—" if tally.empty?

      tally.sort_by { |_, count| -count }.map { |name, count| "#{name} #{count}" }.join(", ")
    end

    def listing_section(runs)
      return nil if runs.empty?

      lines = [ "## 実行ごとの一覧", "" ]
      lines << "| run_id | 判定 | 自己申告 | 終了理由 | HTTP | エラー | ツール | 入力 | 出力 |"
      lines << "|---|---|---|---|---|---|---|---|---|"
      runs.sort_by { |run| run["run_id"].to_s }.each do |run|
        lines << [
          "", run["run_id"], run["verdict"], run["claim"], run["finish_reason"],
          run["http_requests"], run["error_responses"], run["tool_calls"],
          run["input_tokens"], run["output_tokens"], ""
        ].join(" | ").strip
      end
      lines << ""
      lines.join("\n")
    end

    # --- 別のデータセットとの並置 ---------------------------------------

    # 向きが同じかを目で見るための節。優劣を言うためのものではない。
    def comparison_section
      return nil if @against.nil?

      others = load_runs(@against)
      return "## 別のデータセットとの並置\n\n#{@against} に実行記録がありません。\n" if others.empty?

      sets = [ [ @runs_dir, @runs ], [ @against, others ] ]
      [
        "## 別のデータセットとの並置",
        "",
        "各データセットの中で HTML と JSON の差が同じ向きに出るかを見るための節です。",
        "モデルどうしの優劣を言うためのものではありません。数値の絶対値は比べないでください。",
        "トークンの列は置いていません。thinking の有無がデータセットごとに違うと、",
        "出力にも（前のターンの扱いを通じて）入力にも乗るためです。",
        "",
        dataset_legend(sets),
        "",
        comparison_matrix(sets),
        comparison_reference(sets)
      ].compact.join("\n")
    end

    def dataset_legend(sets)
      sets.map do |dir, runs|
        models = runs.map { |run| run["response_model"] || run["model"] }.uniq.compact
        "- `#{File.basename(dir)}`: #{models.join(', ')}（#{runs.size} 件）"
      end.join("\n")
    end

    def comparison_matrix(sets)
      cells = sets.map { |dir, runs| [ dir, group_loop(runs) ] }
      keys = cells.flat_map { |_, grouped| grouped.keys }.uniq.sort_by { |s, c| [ s, order_of(c) ] }
      return nil if keys.empty?

      header = [ "シナリオ", "条件" ] + cells.flat_map do |dir, _|
        name = File.basename(dir)
        [ "成否（#{name}）", "HTTP（#{name}）", "エラー応答（#{name}）", "危険な誤操作（#{name}）" ]
      end

      lines = [ "### 自作ループ", "", "| #{header.join(' | ')} |", "|#{'---|' * header.size}" ]
      keys.each do |key|
        row = [ key.first, key.last ] + cells.flat_map { |_, grouped| loop_columns(grouped[key]) }
        lines << "| #{row.join(' | ')} |"
      end
      lines << ""
      lines.join("\n")
    end

    def loop_columns(cell)
      return [ "—", "—", "—", "—" ] if cell.nil? || cell.empty?

      with_errors = cell.count { |run| run["error_responses"].to_i.positive? }
      dangerous = cell.count { |run| %w[false_success collateral].include?(run["verdict"]) }
      [
        "#{cell.count { |run| run['verdict'] == 'success' }}/#{cell.size}",
        spread(cell, "http_requests"),
        "#{spread(cell, 'error_responses')}・#{with_errors}/#{cell.size}件",
        dangerous.to_s
      ]
    end

    def comparison_reference(sets)
      cells = sets.map { |dir, runs| [ dir, group_reference(runs) ] }
      keys = cells.flat_map { |_, grouped| grouped.keys }.uniq.sort
      return nil if keys.empty?

      header = [ "シナリオ", "条件", "前提の一行" ] + cells.flat_map do |dir, _|
        name = File.basename(dir)
        [ "N（#{name}）", "到達（#{name}）", "success（#{name}）" ]
      end

      lines = [ "### 参考実行", "", "| #{header.join(' | ')} |", "|#{'---|' * header.size}" ]
      keys.each do |(scenario, condition, hint)|
        row = [ scenario, condition, hint.zero? ? "なし" : "あり" ] +
              cells.flat_map { |_, grouped| reference_columns(grouped[[ scenario, condition, hint ]]) }
        lines << "| #{row.join(' | ')} |"
      end
      lines << ""
      lines.join("\n")
    end

    def reference_columns(cell)
      return [ "—", "—", "—" ] if cell.nil? || cell.empty?

      [ cell.size.to_s, reached(cell).to_s,
        cell.count { |run| reference_verdict(run) == "success" }.to_s ]
    end

    def group_loop(runs)
      runs.reject { |run| run["agent"].to_s == "claude_code" }
          .group_by { |run| [ run["scenario"], run["condition"] ] }
    end

    def group_reference(runs)
      runs.select { |run| run["agent"].to_s == "claude_code" }
          .group_by { |run| [ run["scenario"], run["condition"], run["hint"] ? 1 : 0 ] }
    end

    def order_of(condition) = CONDITION_ORDER.index(condition) || CONDITION_ORDER.size

    def spread(cell, key)
      values = cell.map { |run| run[key] }.compact.map(&:to_i)
      return "—" if values.empty?

      "#{median(values)} (#{values.min}〜#{values.max})"
    end

    def median(values)
      sorted = values.sort
      middle = sorted.size / 2
      return sorted[middle] if sorted.size.odd?

      average = (sorted[middle - 1] + sorted[middle]) / 2.0
      (average % 1).zero? ? average.to_i : average.round(1)
    end
  end
end
