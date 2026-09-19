require "test_helper"
require "json"
require "agent/reference/claude_code"

class ReferenceClaudeCodeTest < Minitest::Test
  def build
    Agent::Reference::ClaudeCode.new(
      scenario: nil, condition: nil, origin: "http://localhost:3000",
      transcript: nil, config: nil, app_dir: TODO_APP_DIR, run_dir: "/tmp"
    )
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
end
