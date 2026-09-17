require "json"
require "time"

# 実験中のHTTPやりとりを1リクエスト1行のJSONLで記録するRackミドルウェア。
# ボディ本文は記録しない（エージェント側で記録する）。
class RequestRecorder
  IGNORED_PATH_PREFIXES = [ "/up", "/assets/" ].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    log_path = ENV["EXPERIMENT_LOG"]
    return @app.call(env) if log_path.nil? || log_path.empty?

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    status, headers, body = @app.call(env)
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(3)

    request = Rack::Request.new(env)
    append(log_path, request, status, headers, body, duration_ms) unless ignored?(request.path)

    [ status, headers, body ]
  end

  private

  def ignored?(path)
    IGNORED_PATH_PREFIXES.any? { |prefix| path.start_with?(prefix) }
  end

  def append(log_path, request, status, headers, body, duration_ms)
    entry = {
      time: Time.now.utc.iso8601(3),
      method: request.request_method,
      path: request.fullpath,
      status: status,
      request_bytes: request_bytes(request),
      response_bytes: response_bytes(headers, body),
      accept: request.get_header("HTTP_ACCEPT"),
      content_type: request.content_type,
      response_content_type: header_value(headers, "content-type"),
      duration_ms: duration_ms
    }

    File.open(log_path, "a") { |f| f.puts(JSON.generate(entry)) }
  rescue SystemCallError, IOError
    # 記録の失敗でリクエストを壊さない。
    nil
  end

  def request_bytes(request)
    length = request.content_length
    return length.to_i if length

    input = request.get_header("rack.input")
    return 0 if input.nil?

    position = input.respond_to?(:pos) ? input.pos : nil
    input.rewind if input.respond_to?(:rewind)
    size = input.read&.bytesize || 0
    input.rewind if input.respond_to?(:rewind)
    input.pos = position if position && input.respond_to?(:pos=)
    size
  end

  # Content-Length はアプリ層では付いていないことがあるので、
  # その場合はボディ本文の長さを数える（本文そのものは記録しない）。
  def response_bytes(headers, body)
    length = header_value(headers, "content-length")
    return length.to_i if length

    return 0 unless body.respond_to?(:to_ary)

    body.to_ary.sum { |chunk| chunk.to_s.bytesize }
  end

  def header_value(headers, name)
    headers.each { |key, value| return value if key.to_s.downcase == name }
    nil
  end
end
