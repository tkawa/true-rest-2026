require "json"
require "time"

module Agent
  # runs/**/run.json を集めて発表用の表を書く。数値は中央値（最小〜最大）で示す。
  class Report
    RUNS_DIR = File.expand_path("../../../runs", __dir__).freeze
    VERDICTS = %w[success honest_failure false_success collateral incomplete].freeze
    CONDITION_ORDER = %w[html json json_v2].freeze

    def initialize(runs_dir: RUNS_DIR)
      @runs_dir = runs_dir
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

    def load_runs
      Dir.glob(File.join(@runs_dir, "**", "run.json")).sort.map { |path| JSON.parse(File.read(path)) }
    end

    def summary_section(runs)
      return "実行記録がありません。\n" if runs.empty?

      models = runs.map { |r| r["model"] }.uniq.compact
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

      lines = [ "## 参考実行（Claude Code）", "" ]
      lines << "| シナリオ | 条件 | N | 判定の内訳 | HTTPリクエスト | エラー応答 | ターン数 | バージョン |"
      lines << "|---|---|---|---|---|---|---|---|"
      runs.group_by { |run| [ run["scenario"], run["condition"] ] }.each do |(scenario, condition), cell|
        breakdown = cell.map { |run| run["verdict"] }.tally.map { |k, v| "#{k} #{v}" }.join(", ")
        lines << [
          "", scenario, condition, cell.size, breakdown,
          spread(cell, "http_requests"), spread(cell, "error_responses"), spread(cell, "num_turns"),
          cell.map { |run| run["claude_code_version"] }.uniq.join(", "), ""
        ].join(" | ").strip
      end
      lines << ""
      lines.join("\n")
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
      return "-" if values.empty?

      "#{median(values)} (#{values.min}〜#{values.max})"
    end

    def median(values)
      sorted = values.sort
      middle = sorted.size / 2
      return sorted[middle] if sorted.size.odd?

      ((sorted[middle - 1] + sorted[middle]) / 2.0).round(1)
    end
  end
end
