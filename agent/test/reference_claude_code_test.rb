require "test_helper"
require "json"
require "agent/reference/claude_code"

class ReferenceClaudeCodeTest < Minitest::Test
  Condition = Struct.new(:name, :spec_version, keyword_init: true)
  Scenario = Struct.new(:instruction, keyword_init: true)

  def build(hint: false, condition: nil)
    Agent::Reference::ClaudeCode.new(
      scenario: Scenario.new(instruction: "買い物リストに牛乳を追加して"),
      condition: condition || Condition.new(name: "html"),
      origin: "http://localhost:3000",
      transcript: nil, config: nil, app_dir: TODO_APP_DIR, run_dir: "/tmp", hint: hint
    )
  end

  def test_the_bare_message_has_no_hint
    message = build.send(:build_message, Dir.mktmpdir)

    refute_includes message, Agent::Reference::ClaudeCode::HINT
    assert_includes message, "操作対象: http://localhost:3000/"
  end

  def test_the_hint_adds_one_line_only
    bare = build.send(:build_message, Dir.mktmpdir)
    hinted = build(hint: true).send(:build_message, Dir.mktmpdir)

    assert_equal "#{bare}#{Agent::Reference::ClaudeCode::HINT}\n", hinted
    assert_equal bare.lines.size + 1, hinted.lines.size
  end

  def test_the_hint_is_recorded
    assert_equal true, build(hint: true).send(:parse, STREAM, nil).extra["hint"]
    assert_equal false, build.send(:parse, STREAM, nil).extra["hint"]
  end

  def test_api_key_is_not_passed_to_the_cli
    assert_nil build.send(:child_env).fetch("ANTHROPIC_API_KEY")
  end

  STREAM = [
    { type: "system", subtype: "init", model: "claude-sonnet-5", permissionMode: "auto",
      apiKeySource: "none", tools: %w[Bash Read Write], session_id: "abc" },
    { type: "assistant", message: { content: [
      { type: "text", text: "調べます" },
      { type: "tool_use", name: "Bash", input: {} }
    ] } },
    { type: "assistant", message: { content: [ { type: "tool_use", name: "Bash", input: {} } ] } },
    { type: "assistant", message: { content: [ { type: "tool_use", name: "Read", input: {} } ] } },
    { type: "result", subtype: "success", is_error: false, result: "追加しました。",
      num_turns: 4, total_cost_usd: 0.3, duration_ms: 9000, session_id: "abc",
      usage: { input_tokens: 10, output_tokens: 20, cache_creation_input_tokens: 5,
               cache_read_input_tokens: 0 } }
  ].map { |event| JSON.generate(event) }.join("\n").freeze

  def parse_stream
    build.send(:parse, STREAM, nil)
  end

  def test_tool_calls_are_counted_per_name
    result = parse_stream

    assert_equal 3, result.tool_calls
    assert_equal({ "Bash" => 2, "Read" => 1 }, result.extra["tool_calls_by_name"])
  end

  def test_init_event_records_the_run_conditions
    extra = parse_stream.extra

    assert_equal "claude-sonnet-5", extra["response_model"]
    assert_equal "auto", extra["permission_mode"]
    assert_equal "none", extra["api_key_source"]
    assert_equal %w[Bash Read Write], extra["available_tools"]
  end

  def test_result_event_is_read
    result = parse_stream

    assert_equal "追加しました。", result.final_message
    assert_equal "end_turn", result.finish_reason
    assert_equal 4, result.api_calls
    assert_equal 0.3, result.extra["total_cost_usd"]
  end

  def test_output_without_a_result_event_is_an_error
    result = build.send(:parse, "not json", Struct.new(:exitstatus).new(1))

    assert_equal "api_error", result.finish_reason
    assert_nil result.tool_calls
  end

  def test_allowed_tools_are_one_argument
    config = Struct.new(:model).new("claude-sonnet-5")
    agent = build
    agent.instance_variable_set(:@config, config)

    command = agent.send(:build_command)
    index = command.index("--allowedTools")

    refute_nil index
    assert_equal "Bash(curl:*),Read,Write", command[index + 1]
    assert_includes command, "stream-json"
    assert_includes command, "--verbose"
  end

  def test_user_settings_are_not_loaded
    config = Struct.new(:model).new("claude-sonnet-5")
    agent = build
    agent.instance_variable_set(:@config, config)

    command = agent.send(:build_command)
    index = command.index("--setting-sources")

    refute_nil index
    assert_equal "", command[index + 1]
  end

  def test_setting_sources_are_recorded
    assert_equal "", build.send(:parse, STREAM, nil).extra["setting_sources"]
  end
end
