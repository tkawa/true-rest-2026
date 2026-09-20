require "digest"
require "fileutils"
require "json"
require "time"
require "uri"
require "yaml"

require "agent/http_tool"
require "agent/initial_message"
require "agent/loop"
require "agent/oracle"
require "agent/reference/sanitizer"
require "agent/transcript"

module Agent
  # 動いている任意のサービスに、実験と同じエージェントを一回だけ向ける。
  # サーバの管理も成否の判定もしない。判定は人が記録を読んで行う。
  class Adhoc
    DEFAULT_OUT_ROOT = File.expand_path("../../../runs-scratch/adhoc", __dir__).freeze

    Error = Class.new(StandardError)

    Entry = Struct.new(:url, :spec_path, :spec_body, keyword_init: true) do
      def spec? = !spec_body.nil?

      def spec_sha256 = spec? ? Digest::SHA256.hexdigest(spec_body) : nil
    end

    attr_reader :entry, :origin, :out_dir

    def initialize(entry:, task:, config:, headers: {}, origin: nil, out_dir: nil, progress: nil)
      @entry = entry
      @task = task
      @config = config
      @headers = headers
      # 上書きも同じ正規化を通す。ツールは scheme://host:port で照合するため。
      @origin = origin ? origin_of(origin) : derive_origin
      @out_dir = out_dir || File.join(DEFAULT_OUT_ROOT, Time.now.utc.strftime("%Y%m%dT%H%M%SZ"))
      @progress = progress
    end

    # エージェントに送る最初のユーザーメッセージ。実験と同じ整形を通す。
    def initial_message
      @initial_message ||=
        if entry.spec?
          InitialMessage.for_spec(@task, entry.spec_body)
        else
          InitialMessage.for_url(@task, entry.url)
        end
    end

    def call(agent_factory: method(:build_loop))
      FileUtils.mkdir_p(out_dir)
      File.write(File.join(out_dir, "initial_message.md"), initial_message)

      tool = HttpTool.new(allowed_origin: origin, default_headers: @headers)
      transcript = Transcript.new(File.join(out_dir, "transcript.jsonl"))
      transcript.record_event("initial_message", content: initial_message)

      started = monotonic
      begin
        outcome = agent_factory.call(tool: tool, transcript: guard(transcript), initial_message: initial_message).run
      ensure
        transcript.close
      end

      write_run_json(outcome, tool, ((monotonic - started) * 1000).round)
    end

    private

    # 認証情報を書かせないための薄い包み。記録の経路を一本に絞る。
    def guard(transcript)
      Recorder.new(transcript, @progress)
    end

    def build_loop(tool:, transcript:, initial_message:)
      Loop.new(
        scenario: nil, condition: nil, http_tool: tool, transcript: transcript,
        initial_message: initial_message, config: @config
      )
    end

    def derive_origin
      return origin_of(entry.url) unless entry.spec?

      url = spec_server_url
      raise Error, "仕様書の servers[0].url が絶対URLではありません（--origin で指定してください）: #{url.inspect}" if url.nil?

      origin_of(url)
    end

    def spec_server_url
      data = YAML.safe_load(entry.spec_body, aliases: true)
      url = data.is_a?(Hash) ? data.dig("servers", 0, "url") : nil
      url.to_s.start_with?("http://", "https://") ? url : nil
    rescue Psych::Exception
      nil
    end

    def origin_of(url)
      uri = URI.parse(url.to_s)
      raise Error, "オリジンを取り出せません: #{url.inspect}" unless uri.is_a?(URI::HTTP) && uri.host

      "#{uri.scheme}://#{uri.host}:#{uri.port || uri.default_port}"
    end

    def write_run_json(outcome, tool, wall_time_ms)
      data = {
        "started_at" => Time.now.utc.iso8601,
        "url" => entry.url,
        "spec_path" => entry.spec_path,
        "spec_sha256" => entry.spec_sha256,
        "origin" => origin,
        "task" => @task,
        # 値は残さない。何を付けたかだけ追えるようにする。
        "fixed_header_names" => @headers.keys,
        "model" => @config.model,
        "response_model" => outcome.respond_to?(:response_model) ? outcome.response_model : nil,
        "temperature" => outcome.respond_to?(:temperature) ? outcome.temperature : @config.temperature,
        "max_tool_calls" => @config.max_tool_calls,
        "system_prompt_sha256" => system_prompt_sha256,
        "finish_reason" => outcome.finish_reason,
        "final_message" => outcome.final_message,
        "claim" => claim_of(outcome.final_message),
        "api_calls" => outcome.api_calls,
        "tool_calls" => outcome.tool_calls,
        # サーバ側の記録は無いので、サーバ側の数と混同しない名前にする。
        "client_side_requests" => tool.calls.size,
        "input_tokens" => outcome.input_tokens,
        "output_tokens" => outcome.output_tokens,
        "cache_creation_input_tokens" => outcome.cache_creation_input_tokens,
        "cache_read_input_tokens" => outcome.cache_read_input_tokens,
        "wall_time_ms" => wall_time_ms,
        "tool_call_log" => tool.calls.map { |call| call.to_h.transform_keys(&:to_s) }
      }
      File.write(File.join(out_dir, "run.json"), JSON.pretty_generate(data) + "\n")
      data
    end

    def system_prompt_sha256
      Digest::SHA256.hexdigest(File.read(Loop::SYSTEM_PROMPT_PATH))
    rescue StandardError
      nil
    end

    # オラクルの読み取りを流用する。判定はしない。
    def claim_of(final_message)
      match = Oracle::CLAIM_PATTERN.match(final_message.to_s.lines.map(&:strip).reject(&:empty?).last.to_s)
      match ? match[1] : nil
    end

    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # 記録の前に認証情報を伏せ、ついでに進行を表示する。
    class Recorder
      def initialize(transcript, progress)
        @transcript = transcript
        @progress = progress
      end

      def record_api_call(request:, response:)
        @transcript.record_api_call(
          request: Reference::Sanitizer.redacted_record(request),
          response: Reference::Sanitizer.redacted_record(response)
        )
      end

      def record_tool_call(tool_use, result)
        safe = Reference::Sanitizer.redacted_record(tool_use.to_h)
        @transcript.record_tool_call(safe, result)
        @progress&.call(tool_use.to_h[:input] || tool_use.to_h["input"], result)
      end

      def record_event(name, payload = {})
        @transcript.record_event(name, payload)
      end
    end
  end
end
