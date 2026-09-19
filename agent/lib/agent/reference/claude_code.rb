require "fileutils"
require "json"
require "open3"
require "tmpdir"

module Agent
  module Reference
    # 既製エージェント（Claude Code）を同じ条件で走らせる参考実行。
    # サーバの起動・停止・記録・オラクルはランナーと共有し、ここだけ差し替える。
    class ClaudeCode
      # リポジトリの中で起動すると実装を読まれてしまうので、空の一時ディレクトリで動かす。
      SPEC_FILENAME = "openapi.yaml".freeze
      DEFAULT_ALLOWED_TOOLS = "Bash(curl:*),Read,Write".freeze

      Result = Struct.new(
        :final_message, :finish_reason, :api_calls, :tool_calls,
        :input_tokens, :output_tokens, :cache_creation_input_tokens, :cache_read_input_tokens,
        :extra, keyword_init: true
      )

      def initialize(scenario:, condition:, origin:, transcript:, config:, app_dir:, run_dir:)
        @scenario = scenario
        @condition = condition
        @origin = origin
        @transcript = transcript
        @config = config
        @app_dir = app_dir
        @run_dir = run_dir
      end

      def run
        Dir.mktmpdir("claude-code-reference") do |workdir|
          message = build_message(workdir)
          File.write(File.join(@run_dir, "initial_message.md"), message)
          @transcript.record_event("initial_message", condition: @condition.name, content: message)
          execute(workdir, message)
        end
      end

      def self.version
        out, _, status = Open3.capture3("claude", "--version")
        status.success? ? out.strip : nil
      rescue StandardError
        nil
      end

      private

      def build_message(workdir)
        return "#{@scenario.instruction}\n\n操作対象: #{@origin}/\n" if @condition.spec_version.nil?

        spec = File.read(File.join(@app_dir, "doc", "openapi-#{@condition.spec_version}.yaml"))
                   .gsub("http://localhost:3000/", "#{@origin}/")
        File.write(File.join(workdir, SPEC_FILENAME), spec)
        "#{@scenario.instruction}\n\n操作対象のサービスの仕様書（OpenAPI）は ./#{SPEC_FILENAME} にあります。\n"
      end

      def execute(workdir, message)
        command = build_command
        @transcript.record_event("reference_command", command: command, workdir: workdir)

        # プロンプトは標準入力から渡す（位置引数だと他のフラグに飲まれることがある）。
        stdout, stderr, status = Open3.capture3(child_env, *command, stdin_data: message, chdir: workdir)
        @transcript.record_event("reference_output", stdout: stdout, stderr: stderr, exit_status: status.exitstatus)

        parse(stdout, status)
      end

      # 既製エージェントは自前の認証で動かす。ハーネスの API キーを渡すと、
      # 参考実行ぶんが Messages API に課金されてしまう。
      def child_env
        { "ANTHROPIC_API_KEY" => nil }
      end

      def build_command
        [
          "claude", "-p", "--output-format", "json",
          "--max-turns", "40", "--model", @config.model,
          "--allowedTools", ENV.fetch("REFERENCE_ALLOWED_TOOLS", DEFAULT_ALLOWED_TOOLS)
        ]
      end

      def parse(stdout, status)
        data = JSON.parse(stdout)
        usage = data["usage"] || {}
        Result.new(
          final_message: data["result"].to_s,
          finish_reason: data["is_error"] ? "api_error" : "end_turn",
          api_calls: data["num_turns"].to_i,
          # どのツールを何回使ったかは --output-format json では取れない。
          tool_calls: nil,
          input_tokens: usage["input_tokens"].to_i,
          output_tokens: usage["output_tokens"].to_i,
          cache_creation_input_tokens: usage["cache_creation_input_tokens"].to_i,
          cache_read_input_tokens: usage["cache_read_input_tokens"].to_i,
          extra: {
            "num_turns" => data["num_turns"],
            "total_cost_usd" => data["total_cost_usd"],
            "duration_ms" => data["duration_ms"],
            "session_id" => data["session_id"],
            "allowed_tools" => ENV.fetch("REFERENCE_ALLOWED_TOOLS", DEFAULT_ALLOWED_TOOLS),
            "claude_code_version" => self.class.version
          }
        )
      rescue JSON::ParserError
        Result.new(
          final_message: stdout.to_s, finish_reason: "api_error",
          api_calls: 0, tool_calls: nil, input_tokens: 0, output_tokens: 0,
          cache_creation_input_tokens: 0, cache_read_input_tokens: 0,
          extra: { "exit_status" => status.exitstatus, "claude_code_version" => self.class.version }
        )
      end
    end
  end
end
