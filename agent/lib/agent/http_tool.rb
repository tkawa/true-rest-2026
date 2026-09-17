require "net/http"
require "uri"
require "agent/cookie_jar"

module Agent
  # エージェントに与える唯一のツール。
  # 受け取ったものをそのまま送り、返ってきたものをそのまま返す。
  class HttpTool
    NAME = "http_request".freeze

    DEFINITION = {
      name: NAME,
      description: "対象のWebサービスにHTTPリクエストを送り、レスポンスをそのまま返します。" \
                   "リダイレクトは自動では追従しません。Cookieは同じ実行の中で保持されます。",
      input_schema: {
        type: "object",
        properties: {
          method: { type: "string", enum: %w[GET POST PUT PATCH DELETE] },
          url: { type: "string", description: "絶対URL" },
          headers: {
            type: "object",
            additionalProperties: { type: "string" },
            description: "追加のリクエストヘッダ（任意）"
          },
          body: {
            type: "string",
            description: "リクエストボディ（任意）。Content-Type は headers で指定する"
          }
        },
        required: %w[method url]
      }
    }.freeze

    USER_AGENT = "todo-experiment-agent/1.0".freeze
    RETURNED_HEADERS = %w[content-type content-length location allow cache-control etag].freeze
    MAX_BODY_BYTES = 64 * 1024
    TIMEOUT_SECONDS = 15

    Call = Struct.new(:method, :url, :status, :request_bytes, :response_bytes, keyword_init: true)

    attr_reader :calls

    def initialize(allowed_origin:, cookie_jar: CookieJar.new)
      @allowed_origin = allowed_origin
      @cookie_jar = cookie_jar
      @calls = []
    end

    def call_count = @calls.size

    # ツール結果の本文（文字列）を返す。例外は投げない。
    def call(input)
      method = input["method"] || input[:method]
      url = input["url"] || input[:url]
      headers = input["headers"] || input[:headers] || {}
      body = input["body"] || input[:body]

      uri = parse(url)
      return refuse(method, url) if uri.nil? || origin_of(uri) != @allowed_origin

      perform(method.to_s.upcase, uri, headers, body)
    end

    private

    def parse(url)
      uri = URI.parse(url.to_s)
      uri.is_a?(URI::HTTP) ? uri : nil
    rescue URI::InvalidURIError
      nil
    end

    def origin_of(uri)
      port = uri.port || uri.default_port
      "#{uri.scheme}://#{uri.host}:#{port}"
    end

    def refuse(method, url)
      @calls << Call.new(method: method.to_s, url: url.to_s, status: nil, request_bytes: 0, response_bytes: 0)
      "error: この実行で許可されていないURLです"
    end

    def perform(method, uri, headers, body)
      request = build_request(method, uri, headers, body)
      started_bytes = request.body.to_s.bytesize

      response = Net::HTTP.start(uri.host, uri.port, open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS) do |http|
        http.request(request)
      end

      @cookie_jar.store(response.get_fields("set-cookie"))
      raw_body = response.body.to_s
      @calls << Call.new(
        method: method, url: uri.to_s, status: response.code.to_i,
        request_bytes: started_bytes, response_bytes: raw_body.bytesize
      )

      format_response(response, raw_body)
    rescue StandardError => e
      @calls << Call.new(method: method, url: uri.to_s, status: nil, request_bytes: started_bytes.to_i, response_bytes: 0)
      "error: #{e.class}: #{e.message}"
    end

    def build_request(method, uri, headers, body)
      klass = Net::HTTP.const_get(method.capitalize)
      request = klass.new(uri)
      request["user-agent"] = USER_AGENT
      cookie = @cookie_jar.header
      request["cookie"] = cookie if cookie
      headers.each { |name, value| request[name.to_s] = value.to_s }
      request.body = body.to_s if body
      request
    end

    def format_response(response, raw_body)
      lines = [ "HTTP #{response.code} #{response.message}" ]
      RETURNED_HEADERS.each do |name|
        value = response[name]
        lines << "#{name}: #{value}" if value
      end
      lines << ""
      lines << truncate(raw_body)
      lines.join("\n")
    end

    def truncate(raw_body)
      return raw_body if raw_body.bytesize <= MAX_BODY_BYTES

      remaining = raw_body.bytesize - MAX_BODY_BYTES
      head = raw_body.byteslice(0, MAX_BODY_BYTES).scrub
      "#{head}\n[... 切り詰め: 残り #{remaining} バイト]"
    end
  end
end
