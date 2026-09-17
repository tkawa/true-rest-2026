require "json"
require "time"

module Agent
  # 1イベント1行の JSONL。後から再判定・再集計できるよう、
  # その回に送ったメッセージ全体を残す。
  class Transcript
    def initialize(path)
      @path = path
      @file = File.open(path, "a")
      @file.sync = true
    end

    def record_api_call(request:, response:)
      write("api_call", request: request, response: response)
    end

    def record_tool_call(tool_use, result)
      write("tool_call", tool_use: tool_use, result: result)
    end

    def record_event(name, payload = {})
      write(name, **payload)
    end

    def close = @file.close

    private

    def write(type, **payload)
      @file.puts(JSON.generate({ type: type, at: Time.now.utc.iso8601(3) }.merge(payload)))
    end
  end
end
