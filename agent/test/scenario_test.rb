require "test_helper"
require "agent/scenario"
require "agent/server"

class ScenarioTest < Minitest::Test
  def load_yaml(extra_condition)
    Agent::Scenario.new(
      {
        "id" => "sx", "name" => "x", "instruction" => "x",
        "conditions" => { "html" => {}, "json" => { "spec" => "v1" }, "bad" => extra_condition }
      }
    )
  end

  def test_server_env_defaults_to_empty
    scenario = Agent::Scenario.load("s4")

    assert_equal({}, scenario.condition("json").server_env)
    assert_equal({}, scenario.condition("html").server_env)
  end

  def test_server_env_is_read_from_the_condition
    condition = Agent::Scenario.load("s4").condition("json_terse_nocontent")

    assert_equal "v1-terse-nocontent", condition.spec_version
    assert_equal({ "UPDATE_NO_CONTENT" => "1" }, condition.server_env)
  end

  def test_unknown_server_env_key_is_rejected_at_load
    error = assert_raises(ArgumentError) { load_yaml("server_env" => { "FEATURE_ARCHIVE" => "1" }) }

    assert_includes error.message, "FEATURE_ARCHIVE"
  end

  def test_feature_title_limit_defaults_to_false
    refute Agent::Scenario.load("s4").feature_title_limit
    assert Agent::Scenario.load("s5").feature_title_limit
  end

  def test_s5_title_is_over_the_limit
    title = Agent::Scenario.load("s5").instruction[/「月次レポート提出（.*）」に/]

    assert_operator title.length - 4, :>, 100
  end

  def server(**options)
    Agent::Server.new(
      app_dir: TODO_APP_DIR, port: 3999, database_path: "/tmp/x.sqlite3",
      log_path: "/tmp/x.jsonl", server_log_path: "/tmp/x.log", **options
    )
  end

  def test_server_env_is_unchanged_without_switches
    env = server.env

    refute env.key?("UPDATE_NO_CONTENT") && env["UPDATE_NO_CONTENT"]
    refute env["FEATURE_TITLE_LIMIT"]
    refute env["FEATURE_ARCHIVE"]
  end

  def test_server_env_carries_extra_env_and_title_limit
    env = server(feature_title_limit: true, extra_env: { "UPDATE_NO_CONTENT" => "1" }).env

    assert_equal "1", env["UPDATE_NO_CONTENT"]
    assert_equal "1", env["FEATURE_TITLE_LIMIT"]
    assert_equal "experiment", env["RAILS_ENV"]
  end
end
