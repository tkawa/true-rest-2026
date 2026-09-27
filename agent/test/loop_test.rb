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
    attr_reader :content, :stop_reason, :usage, :model

    def initialize(content:, stop_reason:, usage:, model: "claude-sonnet-5-20260101")
      @content = content
      @stop_reason = stop_reason
      @usage = usage
      @model = model
    end

    def to_h = { content: content.map(&:to_h), stop_reason: stop_reason, model: model }
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

  def build(responses, max_tool_calls: 25, tool: StubTool.new, thinking: "disabled")
    config = Agent::Config.default(max_tool_calls: max_tool_calls, thinking: thinking)
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
    assert_equal "claude-sonnet-5-20260101", result.response_model
  end

  # 思考を切れないモデルでは、応答に thinking ブロックが入る。
  # 署名付きのまま assistant メッセージに積み直さないと次のターンが通らない。
  def test_a_thinking_block_survives_the_round_trip
    thinking = Block.new(type: "thinking", text: "考え中")
    with_thinking = Response.new(
      content: [ thinking,
                 Block.new(type: "tool_use", id: "tu_1", name: "http_request",
                           input: { "method" => "GET", "url" => "http://localhost:3000/" }) ],
      stop_reason: "tool_use", usage: usage
    )
    loop_agent, tool = build([ with_thinking, end_response("できました。\n結果: 完了") ])

    result = loop_agent.run

    assert_equal 1, tool.call_count
    assert_equal "end_turn", result.finish_reason
    # 2回目の送信に thinking ブロックがそのまま載っている
    sent = loop_agent.instance_variable_get(:@client).requests.last[:messages]
    assistant = sent.find { |message| message[:role] == "assistant" }
    types = Array(assistant[:content]).map { |block| block[:type] || block["type"] }

    assert_includes types, "thinking"
    assert_includes types, "tool_use"
  end

  def test_the_final_message_ignores_thinking_blocks
    response = Response.new(
      content: [ Block.new(type: "thinking", text: "内心の独り言"),
                 Block.new(type: "text", text: "報告です。\n結果: 完了") ],
      stop_reason: "end_turn", usage: usage
    )
    loop_agent, = build([ response ])

    result = loop_agent.run

    assert_equal "報告です。\n結果: 完了", result.final_message
    refute_includes result.final_message, "内心の独り言"
  end

  def test_the_thinking_mode_is_sent_and_recorded
    loop_agent, = build([ end_response("結果: 完了") ], thinking: "adaptive")

    result = loop_agent.run
    request = loop_agent.instance_variable_get(:@client).requests.first

    assert_equal({ type: "adaptive" }, request[:thinking])
    assert_equal "adaptive", result.thinking
  end

  def test_max_tokens_is_kept_as_the_finish_reason
    cut_off = Response.new(
      content: [ Block.new(type: "text", text: "途中で切れた") ],
      stop_reason: "max_tokens", usage: usage
    )
    loop_agent, = build([ cut_off ])

    result = loop_agent.run

    assert_equal "max_tokens", result.finish_reason
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
    assert_equal html_request[:thinking], json_request[:thinking]
    assert_equal 0, html_request[:temperature]
    assert_equal({ type: "disabled" }, html_request[:thinking])
  end
end
