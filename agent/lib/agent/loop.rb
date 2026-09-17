require "anthropic"
require "agent/http_tool"

module Agent
  # Messages API を直接呼ぶ手書きのループ。
  # 上限・記録・使用量の集計を自分で握るため、SDK の tool runner は使わない。
  class Loop
    SYSTEM_PROMPT_PATH = File.expand_path("../../prompts/system.md", __dir__).freeze
    MAX_TOKENS = 4096
    API_RETRIES = 3

    Result = Struct.new(
      :final_message, :finish_reason, :api_calls, :tool_calls,
      :input_tokens, :output_tokens, :cache_creation_input_tokens, :cache_read_input_tokens,
      keyword_init: true
    )

    def initialize(scenario:, condition:, http_tool:, transcript:, initial_message:, config:, client: nil)
      @scenario = scenario
      @condition = condition
      @tool = http_tool
      @transcript = transcript
      @initial_message = initial_message
      @config = config
      @client = client || Anthropic::Client.new(max_retries: 0)
      @usage = Hash.new(0)
      @api_calls = 0
    end

    def system_prompt = File.read(SYSTEM_PROMPT_PATH)

    def run
      messages = [ { role: "user", content: @initial_message } ]
      final_message = ""
      finish_reason = "end_turn"
      deadline = monotonic + @config.timeout_seconds

      loop do
        response = call_api(messages)
        return timed_out(final_message) if response == :api_error

        messages << { role: "assistant", content: response.to_h[:content] }
        final_message = text_of(response)

        break unless response.stop_reason.to_s == "tool_use"

        messages << { role: "user", content: tool_results(response) }

        if @tool.call_count >= @config.max_tool_calls
          finish_reason = "tool_limit"
          break
        end

        if monotonic > deadline
          finish_reason = "timeout"
          break
        end
      end

      result(final_message, finish_reason)
    end

    private

    def call_api(messages)
      attempt = 0
      begin
        attempt += 1
        params = {
          model: @config.model, max_tokens: MAX_TOKENS, temperature: @config.temperature,
          system: system_prompt, tools: [ HttpTool::DEFINITION ], messages: messages
        }
        response = @client.messages.create(params)
        @api_calls += 1
        accumulate(response.usage)
        @transcript.record_api_call(request: params, response: response.to_h)
        response
      rescue Anthropic::Errors::APIError => e
        @transcript.record_event("api_error", attempt: attempt, error: "#{e.class}: #{e.message}")
        if attempt < API_RETRIES
          sleep(2**attempt)
          retry
        end
        :api_error
      end
    end

    def tool_results(response)
      response.content.select { |block| block.type.to_s == "tool_use" }.map do |use|
        input = use.input.is_a?(Hash) ? stringify(use.input) : {}
        result = @tool.call(input)
        @transcript.record_tool_call({ id: use.id, name: use.name, input: input }, result)
        { type: "tool_result", tool_use_id: use.id, content: result }
      end
    end

    def stringify(hash)
      hash.to_h { |key, value| [ key.to_s, value.is_a?(Hash) ? stringify(value) : value ] }
    end

    def text_of(response)
      response.content.select { |block| block.type.to_s == "text" }.map(&:text).join("\n").strip
    end

    def accumulate(usage)
      return if usage.nil?

      %i[input_tokens output_tokens cache_creation_input_tokens cache_read_input_tokens].each do |key|
        @usage[key] += usage.respond_to?(key) ? usage.public_send(key).to_i : 0
      end
    end

    def timed_out(final_message) = result(final_message, "api_error")

    def result(final_message, finish_reason)
      Result.new(
        final_message: final_message, finish_reason: finish_reason,
        api_calls: @api_calls, tool_calls: @tool.call_count,
        input_tokens: @usage[:input_tokens], output_tokens: @usage[:output_tokens],
        cache_creation_input_tokens: @usage[:cache_creation_input_tokens],
        cache_read_input_tokens: @usage[:cache_read_input_tokens]
      )
    end

    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
