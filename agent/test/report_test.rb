require "test_helper"
require "json"
require "agent/report"

class ReportTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("report-test")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def write_run(scenario:, condition:, agent:, **attrs)
    dir = File.join(@dir, scenario, condition, "#{scenario}-#{condition}-#{attrs.fetch(:seq, 1)}")
    FileUtils.mkdir_p(dir)
    data = {
      "run_id" => File.basename(dir), "scenario" => scenario, "condition" => condition,
      "agent" => agent, "model" => "claude-sonnet-5", "temperature" => nil,
      "max_tool_calls" => 25, "started_at" => "2026-09-19T00:00:00Z",
      "verdict" => "incomplete", "expected_changes_satisfied" => false,
      "unexpected_changes" => [], "http_requests" => 0, "error_responses" => 0,
      "tool_calls" => 0, "input_tokens" => 0, "output_tokens" => 0
    }.merge(attrs.transform_keys(&:to_s))
    File.write(File.join(dir, "run.json"), JSON.generate(data))
  end

  def report = Agent::Report.new(runs_dir: @dir)

  def write_run_in(dir, scenario:, condition:, agent:, **attrs)
    path = File.join(dir, scenario, condition, "#{scenario}-#{condition}-#{attrs.fetch(:seq, 1)}")
    FileUtils.mkdir_p(path)
    data = {
      "run_id" => File.basename(path), "scenario" => scenario, "condition" => condition,
      "agent" => agent, "model" => "m", "response_model" => attrs.delete(:response_model) || "m",
      "temperature" => nil, "max_tool_calls" => 25, "started_at" => "2026-09-27T00:00:00Z",
      "verdict" => "success", "expected_changes_satisfied" => true,
      "unexpected_changes" => [], "http_requests" => 2, "error_responses" => 0,
      "tool_calls" => 2, "input_tokens" => 1, "output_tokens" => 1
    }.merge(attrs.transform_keys(&:to_s))
    File.write(File.join(path, "run.json"), JSON.generate(data))
  end

  def test_reference_runs_are_judged_on_the_database_only
    write_run(scenario: "s2", condition: "json", agent: "claude_code",
              verdict: "incomplete", expected_changes_satisfied: true)

    assert_includes report.call, "success 1"
    refute_includes report.call, "incomplete 1"
  end

  def test_reference_run_without_the_expected_change_is_no_change
    write_run(scenario: "s2", condition: "html", agent: "claude_code",
              verdict: "honest_failure", expected_changes_satisfied: false)

    assert_includes report.call, "no_change 1"
  end

  def test_reference_run_with_damage_is_collateral
    write_run(scenario: "s2", condition: "html", agent: "claude_code",
              expected_changes_satisfied: true,
              unexpected_changes: [ { "table" => "todos", "op" => "delete", "id" => 4 } ])

    assert_includes report.call, "collateral 1"
  end

  def test_loop_runs_keep_the_oracle_verdict
    write_run(scenario: "s2", condition: "html", agent: "loop",
              verdict: "false_success", expected_changes_satisfied: false)

    assert_includes report.call, "false_success 1"
  end

  def test_fake_runs_are_excluded_by_default
    write_run(scenario: "s2", condition: "html", agent: "fake:correct", verdict: "success")

    assert_includes report.call, "実行記録がありません"
    assert_includes Agent::Report.new(runs_dir: @dir, include_fake: true).call, "success 1"
  end

  def test_hint_runs_are_a_separate_row
    write_run(scenario: "s2", condition: "html", agent: "claude_code", seq: 1,
              expected_changes_satisfied: false, hint: false)
    write_run(scenario: "s2", condition: "html", agent: "claude_code", seq: 2,
              expected_changes_satisfied: true, hint: true)

    text = report.call

    assert_includes text, "| s2 | html | なし | 1 | 0 | no_change 1"
    assert_includes text, "| s2 | html | あり | 1 | 0 | success 1"
  end

  def test_the_reached_column_separates_the_two_kinds_of_failure
    write_run(scenario: "s2", condition: "html", agent: "claude_code", seq: 1,
              expected_changes_satisfied: false, http_requests: 0)
    write_run(scenario: "s2", condition: "html", agent: "claude_code", seq: 2,
              expected_changes_satisfied: false, http_requests: 4)
    write_run(scenario: "s2", condition: "html", agent: "claude_code", seq: 3,
              expected_changes_satisfied: true, http_requests: 5)

    # N=3、到達 2、success 1 → 到達しなかった1、到達したが止まった1、完遂1
    assert_includes report.call, "| s2 | html | なし | 3 | 2 | success 1, no_change 2"
  end

  def test_refusals_are_counted_apart_from_other_incompletes
    write_run(scenario: "s2", condition: "html", agent: "loop", seq: 1,
              verdict: "incomplete", finish_reason: "refusal")
    write_run(scenario: "s2", condition: "html", agent: "loop", seq: 2,
              verdict: "incomplete", finish_reason: "refusal")
    write_run(scenario: "s2", condition: "html", agent: "loop", seq: 3,
              verdict: "incomplete", finish_reason: "tool_limit")

    assert_includes report.call, "incomplete 3（refusal 2）"
  end

  def test_api_errors_are_excluded_from_the_cell_and_counted_in_n
    write_run(scenario: "s4", condition: "json", agent: "loop", seq: 1,
              verdict: "incomplete", finish_reason: "api_error")
    write_run(scenario: "s4", condition: "json", agent: "loop", seq: 2,
              verdict: "honest_failure", finish_reason: "end_turn")

    text = report.call

    assert_includes text, "| s4 | json | 1（api_error 除外 1/2） | honest_failure 1 |"
    refute_includes text, "incomplete 1"
  end

  def test_a_cell_without_refusals_is_unchanged
    write_run(scenario: "s2", condition: "html", agent: "loop", verdict: "success",
              finish_reason: "end_turn")

    text = report.call

    assert_includes text, "success 1"
    refute_includes text, "refusal"
  end

  # --- 別のデータセットとの並置 ---------------------------------------

  def test_without_against_the_output_is_unchanged
    write_run(scenario: "s3", condition: "json", agent: "loop")

    refute_includes report.call, "別のデータセットとの並置"
  end

  def test_the_comparison_section_puts_both_datasets_side_by_side
    other = Dir.mktmpdir("report-test-other")
    write_run_in(@dir, scenario: "s3", condition: "json", agent: "loop",
                 response_model: "model-a", error_responses: 1, verdict: "success")
    write_run_in(other, scenario: "s3", condition: "json", agent: "loop",
                 response_model: "model-b", error_responses: 0, verdict: "collateral",
                 expected_changes_satisfied: false)

    text = Agent::Report.new(runs_dir: @dir, against: other).call

    assert_includes text, "別のデータセットとの並置"
    assert_includes text, "model-a"
    assert_includes text, "model-b"
    # 成否・エラー応答・危険な誤操作が、データセットごとに並ぶ
    assert_includes text, "| s3 | json | 1/1 | 2 (2〜2) | 1 (1〜1)・1/1件 | 0 | 0/1 | 2 (2〜2) | 0 (0〜0)・0/1件 | 1 |"
  ensure
    FileUtils.rm_rf(other)
  end

  def test_the_comparison_section_covers_reference_runs
    other = Dir.mktmpdir("report-test-other")
    write_run_in(@dir, scenario: "s2", condition: "html", agent: "claude_code",
                 hint: false, http_requests: 0, expected_changes_satisfied: false)
    write_run_in(other, scenario: "s2", condition: "html", agent: "claude_code",
                 hint: false, http_requests: 4, expected_changes_satisfied: true)

    text = Agent::Report.new(runs_dir: @dir, against: other).call

    assert_includes text, "### 参考実行"
    assert_includes text, "| s2 | html | なし | 1 | 0 | 0 | 1 | 1 | 1 |"
  ensure
    FileUtils.rm_rf(other)
  end

  def test_an_empty_comparison_directory_is_reported
    other = Dir.mktmpdir("report-test-other")
    write_run(scenario: "s3", condition: "json", agent: "loop")

    assert_includes Agent::Report.new(runs_dir: @dir, against: other).call, "実行記録がありません"
  ensure
    FileUtils.rm_rf(other)
  end

  def test_the_comparison_section_says_it_is_not_a_ranking
    other = Dir.mktmpdir("report-test-other")
    write_run_in(@dir, scenario: "s3", condition: "json", agent: "loop")
    write_run_in(other, scenario: "s3", condition: "json", agent: "loop")

    assert_includes Agent::Report.new(runs_dir: @dir, against: other).call,
                    "モデルどうしの優劣を言うためのものではありません"
  ensure
    FileUtils.rm_rf(other)
  end

  def test_the_reference_table_says_what_is_comparable
    write_run(scenario: "s2", condition: "json", agent: "claude_code",
              expected_changes_satisfied: true)

    assert_includes report.call, "サーバ側のHTTPリクエスト数だけです"
  end
end
