require "test_helper"
require "json"
require "agent/http_tool"

# 生のボディをそのまま返すツールが、大きな応答や不正なバイト列でも壊れないこと。
class HttpToolTest < Minitest::Test
  # Net::HTTP の応答の代わりに使う最小限の入れ物。
  class StubResponse
    attr_reader :code, :message, :body

    def initialize(code:, message:, body:, headers: {})
      @code = code
      @message = message
      @body = body
      @headers = headers
    end

    def [](name) = @headers[name]

    def get_fields(_name) = nil
  end

  def tool = @tool ||= Agent::HttpTool.new(allowed_origin: "http://localhost:3000")

  def format(response)
    tool.send(:format_response, response, response.body)
  end

  def test_large_non_ascii_body_is_truncated
    body = ("日本語" * 30_000).dup.force_encoding(Encoding::ASCII_8BIT)
    assert_operator body.bytesize, :>, Agent::HttpTool::MAX_BODY_BYTES

    text = format(StubResponse.new(code: "200", message: "OK", body: body))

    assert_includes text, "[... 切り詰め: 残り"
    assert text.valid_encoding?
    assert_equal Encoding::UTF_8, text.encoding
  end

  def test_invalid_bytes_survive_json_generation
    body = "先頭\xff\xfe末尾".dup.force_encoding(Encoding::ASCII_8BIT)

    text = format(StubResponse.new(code: "200", message: "OK", body: body))

    assert text.valid_encoding?
    assert_includes text, "先頭"
    JSON.generate({ "result" => text })
  end

  def test_small_utf8_body_is_returned_as_is
    body = "こんにちは".dup.force_encoding(Encoding::ASCII_8BIT)

    text = format(StubResponse.new(code: "200", message: "OK", body: body,
                                   headers: { "content-type" => "text/plain" }))

    assert_equal "HTTP 200 OK\ncontent-type: text/plain\n\nこんにちは", text
  end

  def test_only_allowed_headers_are_returned
    response = StubResponse.new(
      code: "302", message: "Found", body: "",
      headers: { "location" => "http://localhost:3000/lists/2", "x-request-id" => "abc" }
    )

    text = format(response)

    assert_includes text, "location: http://localhost:3000/lists/2"
    refute_includes text, "x-request-id"
  end

  def test_other_origins_are_refused_without_sending
    result = tool.call("method" => "GET", "url" => "http://example.com/")

    assert_equal "error: この実行で許可されていないURLです", result
    assert_nil tool.calls.first.status
  end
end
