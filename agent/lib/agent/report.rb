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

    def initialize(runs_dir: ENV.fetch("RUNS_DIR", RUNS_DIR), include_fake: false)
      @runs_dir = runs_dir
      @include_fake = include_fake
      @runs = load_runs
    end

    def call
      loop_runs, reference_runs = @runs.partition { |run| run["agent"].to_s != "claude_code" }
      [
        "# 実験結果",
        "",
        summary_section(loop_runs),
        matrix_section(loop_runs),
        reference_section(reference_runs),
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
    def load_runs
      runs = Dir.glob(File.join(@runs_dir, "**", "run.json")).sort.map { |path| JSON.parse(File.read(path)) }
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
      breakdown = VERDICTS.filter_map do |verdict|
        count = cell.count { |run| run["verdict"] == verdict }
        "#{verdict} #{count}" if count.positive?
      end.join(", ")

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
        "判定はDB差分だけで出しています（素のシステムプロンプトでは自己申告の行が付かないため）。",
        "「前提の一行」は、初期メッセージに「このサービスには HTTP でアクセスできます。」を足したかどうかです。",
        "#{setting_sources_note(runs)}",
        "#{claude_md_note(runs)}",
        "上の表と直接比べられるのは、サーバ側のHTTPリクエスト数だけです。",
        "ツール呼び出しの数え方が両者で異なります（自作ループは `http_request` の回数、",
        "こちらは CLI が使った全ツールの回数）。",
        ""
      ]
      lines << "| シナリオ | 条件 | 前提の一行 | N | 判定の内訳 | HTTPリクエスト | エラー応答 | ツール呼び出し | ツールの内訳 | ターン数 | バージョン |"
      lines << "|---|---|---|---|---|---|---|---|---|---|---|"
      grouped = runs.group_by { |run| [ run["scenario"], run["condition"], run["hint"] ? 1 : 0 ] }
      grouped.sort_by(&:first).each do |(scenario, condition, hint), cell|
        breakdown = REFERENCE_VERDICTS.filter_map do |verdict|
          count = cell.count { |run| reference_verdict(run) == verdict }
          "#{verdict} #{count}" if count.positive?
        end.join(", ")
        lines << [
          "", scenario, condition, hint.zero? ? "なし" : "あり", cell.size, breakdown,
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
