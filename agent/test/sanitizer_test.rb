require "test_helper"
require "json"
require "agent/reference/sanitizer"

class SanitizerTest < Minitest::Test
  Sanitizer = Agent::Reference::Sanitizer

  SYSTEM_EVENT = {
    type: "system", subtype: "init",
    cwd: "/private/var/folders/xx/T/claude-code-reference-1",
    session_id: "abc", tools: %w[Bash Read], model: "claude-sonnet-5",
    permissionMode: "auto", apiKeySource: "none", claude_code_version: "2.1.275",
    output_style: "clear-japanese",
    slash_commands: %w[secret-command],
    skills: %w[secret-skill],
    plugins: [ { name: "internal", path: "/Users/someone/.claude/plugins/internal" } ],
    memory_paths: { auto: "/Users/someone/.claude/projects/x/memory/" },
    messaging_socket_path: "/tmp/cc-socks/123.sock"
  }.freeze

  def stream
    [
      JSON.generate(SYSTEM_EVENT),
      JSON.generate(type: "assistant", message: { content: [ { type: "tool_use", name: "Bash", input: { command: "curl http://localhost:3000/" } } ] }),
      JSON.generate(type: "result", is_error: false, result: "終わりました", num_turns: 3)
    ].join("\n") + "\n"
  end

  def sanitized = Sanitizer.stream(stream, home: "/Users/someone")

  def events = sanitized.lines.map { |line| JSON.parse(line) }

  def test_only_allowlisted_system_keys_survive
    system_event = events.first

    assert_equal %w[type subtype model permissionMode apiKeySource tools claude_code_version].sort,
                 system_event.keys.sort
    assert_equal "claude-sonnet-5", system_event["model"]
    assert_equal %w[Bash Read], system_event["tools"]
  end

  def test_environment_details_are_gone
    text = sanitized

    %w[output_style slash_commands skills plugins memory_paths messaging_socket_path
       secret-command secret-skill cc-socks].each do |needle|
      refute_includes text, needle
    end
    refute_includes text, "/Users/someone"
    refute_includes text, "/var/folders"
  end

  def test_other_events_are_kept
    assistant, result = events[1], events[2]

    assert_equal "Bash", assistant.dig("message", "content", 0, "name")
    assert_equal "終わりました", result["result"]
    assert_equal 3, result["num_turns"]
  end

  def test_paths_are_replaced_with_placeholders
    text = Sanitizer.redact(
      "cwd=/private/var/folders/xx/T/w home=/Users/someone sock=/tmp/cc-socks/9.sock",
      home: "/Users/someone", workdir: "/private/var/folders/xx/T/w"
    )

    assert_equal "cwd=<WORKDIR> home=<HOME> sock=<SOCKET>", text
  end

  def test_the_bare_var_form_of_the_workdir_is_replaced_too
    text = Sanitizer.redact("/var/folders/xx/T/w/openapi.yaml",
                            home: "/Users/someone", workdir: "/private/var/folders/xx/T/w")

    assert_equal "<WORKDIR>/openapi.yaml", text
  end
end
