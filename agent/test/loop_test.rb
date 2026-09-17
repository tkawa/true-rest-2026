require "test_helper"
require "agent/config"
require "agent/loop"
require "agent/scenario"
require "agent/transcript"

# 実APIを呼ばずに、ループの制御（ツール往復、上限、使用量の集計）を確かめる。
class LoopTest < Minitest::Test
  Block = Struct.new(:type, :id, :name, :input, :text, keyword_init: true)
  Usage = Struct.new(:input_tokens, :output_tokens, :cache_creation_input_tokens,
                     :cache_read_input_tokens, keyword_init: true)

  class Response
    attr_reader :content, :stop_reason, :usage

    def initialize(content:, stop_reason:, usage:)
      @content = content
      @stop_reason = stop_reason
      @usage = usage
    end

    def to_h = { content: content.map(&:to_h), stop_reason: stop_reason }
  end

  class StubClient
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def messages = self

    def create(params)
      @requests << params
      @responses.shift || raise("応答が足りません")
    end
  end

  class StubTool
    attr_reader :inputs, :call_count

    def initialize(limit: 99)
      @inputs = []
      @call_count = 0
      @limit = limit
    end

    def call(input)
      @inputs << input
      @call_count += 1
      "HTTP 200 OK\n\nbody"
    end
  end

  def usage(input: 100, output: 20)
    Usage.new(input_tokens: input, output_tokens: output,
              cache_creation_input_tokens: 0, cache_read_input_tokens: 0)
  end

  def tool_use_response(id: "tu_1")
    Response.new(
      content: [ Block.new(type: "tool_use", id: id, name: "http_request",
                           input: { "method" => "GET", "url" => "http://localhost:3000/" }) ],
      stop_reason: "tool_use", usage: usage
    )
  end

  def end_response(text)
    Response.new(content: [ Block.new(type: "text", text: text) ], stop_reason: "end_turn", usage: usage)
  end

  def build(responses, max_tool_calls: 25, tool: StubTool.new)
    config = Agent::Config.default(max_tool_calls: max_tool_calls)
    transcript = Agent::Transcript.new(File.join(Dir.mktmpdir, "transcript.jsonl"))
    loop_agent = Agent::Loop.new(
      scenario: Agent::Scenario.load("s0"), condition: Agent::Scenario::Condition.new(name: "html"),
      http_tool: tool, transcript: transcript, initial_message: "指示",
      config: config, client: StubClient.new(responses)
    )
    [ loop_agent, tool ]
  end

  def test_tool_round_trip_then_end_turn
    loop_agent, tool = build([ tool_use_response, end_response("できました。\n結果: 完了") ])

    result = loop_agent.run

    assert_equal "end_turn", result.finish_reason
    assert_equal "できました。\n結果: 完了", result.final_message
    assert_equal 1, tool.call_count
    assert_equal 2, result.api_calls
    assert_equal 200, result.input_tokens
    assert_equal 40, result.output_tokens
  end

  def test_tool_limit_stops_the_loop
    responses = Array.new(5) { tool_use_response }
    loop_agent, tool = build(responses, max_tool_calls: 2)

    result = loop_agent.run

    assert_equal "tool_limit", result.finish_reason
    assert_equal 2, tool.call_count
  end

  def test_both_conditions_send_the_same_system_prompt_and_tools
    loop_agent, = build([ end_response("結果: 完了") ])
    loop_agent.run
    html_request = loop_agent.instance_variable_get(:@client).requests.first

    json_loop, = build([ end_response("結果: 完了") ])
    json_loop.run
    json_request = json_loop.instance_variable_get(:@client).requests.first

    assert_equal html_request[:system], json_request[:system]
    assert_equal html_request[:tools], json_request[:tools]
    assert_equal 0, html_request[:temperature]
  end
end
