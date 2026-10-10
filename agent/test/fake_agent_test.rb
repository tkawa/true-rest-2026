require "test_helper"
require "agent/config"
require "agent/fake_agent"
require "agent/runner"
require "agent/scenario"

# §11 の疑似エージェントの表。ランナー・ツール・オラクルが正しいことを確かめる。
class FakeAgentTest < Minitest::Test
  PORT = Integer(ENV.fetch("TEST_PORT", 3007))

  def run_fake(script, scenario_id, condition_name)
    config = Agent::Config.default(port: PORT, agent_name: "fake:#{script}")
    factory = lambda do |scenario:, condition:, http_tool:, origin:, transcript:, **|
      Agent::FakeAgent.new(
        script: script, scenario: scenario, condition: condition,
        http_tool: http_tool, origin: origin, transcript: transcript
      )
    end
    Agent::Runner.new(
      scenario: Agent::Scenario.load(scenario_id), condition_name: condition_name,
      config: config, agent_factory: factory
    ).call
  end

  def test_correct_s2_html
    assert_equal "success", run_fake("correct", "s2", "html")["verdict"]
  end

  def test_correct_s2_json
    assert_equal "success", run_fake("correct", "s2", "json")["verdict"]
  end

  def test_correct_s1_html
    assert_equal "success", run_fake("correct", "s1", "html")["verdict"]
  end

  def test_wrong_list_s2_json
    assert_equal "collateral", run_fake("wrong_list", "s2", "json")["verdict"]
  end

  def test_false_claim_s4_json
    assert_equal "false_success", run_fake("false_claim", "s4", "json")["verdict"]
  end

  def test_give_up_s3_html
    assert_equal "success", run_fake("give_up", "s3", "html")["verdict"]
  end

  def test_give_up_s3_json
    assert_equal "success", run_fake("give_up", "s3", "json")["verdict"]
  end

  def test_give_up_s2_html
    assert_equal "honest_failure", run_fake("give_up", "s2", "html")["verdict"]
  end

  def test_give_up_s2_json
    assert_equal "honest_failure", run_fake("give_up", "s2", "json")["verdict"]
  end

  def test_wander_s2_html_is_protocol_violation
    data = run_fake("wander", "s2", "html")

    assert data["protocol_violation"]
    assert_equal [ "/api/lists" ], data["violating_paths"]
  end

  def test_http_requests_matches_requests_jsonl
    data = run_fake("correct", "s2", "json")

    assert_equal data["tool_calls"], data["http_requests"]
  end

  def test_each_run_starts_from_the_snapshot
    first = run_fake("correct", "s2", "json")
    second = run_fake("give_up", "s2", "json")

    assert_equal "success", first["verdict"]
    assert_equal "honest_failure", second["verdict"]
  end

  def test_correct_s7_html_and_json
    %w[html json json_situated].each do |condition|
      data = run_fake("correct", "s7", condition)

      assert_equal "success", data["verdict"], condition
      assert_equal "due", data["seed"]
      assert_equal true, data["feature_due"]
      assert_equal "2026-03-04", data["today"]
    end
  end

  def test_run_json_records_default_seed_and_due_settings
    data = run_fake("give_up", "s0", "html")

    assert_equal "default", data["seed"]
    assert_equal false, data["feature_due"]
    assert_nil data["today"]
  end

  def test_server_env_is_recorded_for_json_situated
    data = run_fake("give_up", "s7", "json_situated")

    assert_equal({ "API_SITUATED" => "1" }, data["server_env"])
    assert_equal "honest_failure", data["verdict"]
  end
end
