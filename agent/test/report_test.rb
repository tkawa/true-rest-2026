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

  def test_the_reference_table_says_what_is_comparable
    write_run(scenario: "s2", condition: "json", agent: "claude_code",
              expected_changes_satisfied: true)

    assert_includes report.call, "サーバ側のHTTPリクエスト数だけです"
  end
end
