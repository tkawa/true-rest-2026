require "test_helper"
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

  def test_allowed_tools_are_one_argument
    config = Struct.new(:model).new("claude-sonnet-5")
    agent = build
    agent.instance_variable_set(:@config, config)

    command = agent.send(:build_command)
    index = command.index("--allowedTools")

    refute_nil index
    assert_equal "Bash(curl:*),Read,Write", command[index + 1]
  end
end
