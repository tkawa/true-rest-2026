require "anthropic"
require "digest"
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
      :temperature, :response_model, keyword_init: true
    )

    # 新しいモデルは temperature を受け付けない。指定できるモデルでは 0 を送り、
    # 拒否されたら外して送り直す。どちらの条件も同じ経路を通るので公平性は変わらない。
    TEMPERATURE_DEPRECATED = /`temperature` is deprecated/

    # 既定で思考する（thinking_tokens が出る）モデルがあるので明示的に切る。
    # 両条件で同じ設定にし、出力トークンの比較を素の応答だけで行う。
    THINKING_DISABLED = { type: "disabled" }.freeze

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
      @temperature = config.temperature
      @response_model = nil
    end

    # 実際に送った temperature（外した場合は nil）。
    attr_reader :temperature

    def system_prompt = File.read(SYSTEM_PROMPT_PATH)

    # プロンプトを変えたら値が変わる。両条件で同一であることの証拠にもなる。
    def system_prompt_sha256 = Digest::SHA256.hexdigest(system_prompt)

    def run
      messages = [ { role: "user", content: @initial_message } ]
      final_message = ""
      finish_reason = "end_turn"
      deadline = monotonic + @config.timeout_seconds

      loop do
        response = call_api(messages)
        return api_failed(final_message) if response == :api_error

        messages << { role: "assistant", content: response.to_h[:content] }
        final_message = text_of(response)

        unless response.stop_reason.to_s == "tool_use"
          # max_tokens や refusal で止まった場合も、そのまま終了理由に残す。
          finish_reason = response.stop_reason.to_s
          break
        end

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
          model: @config.model, max_tokens: MAX_TOKENS,
          system: system_prompt, tools: [ HttpTool::DEFINITION ], messages: messages,
          thinking: THINKING_DISABLED
        }
        params[:temperature] = @temperature unless @temperature.nil?
        response = @client.messages.create(params)
        @api_calls += 1
        # 設定値はエイリアスのことがあるので、実際に使われたモデルIDを残す。
        @response_model ||= response.model.to_s
        accumulate(response.usage)
        @transcript.record_api_call(request: params, response: response.to_h)
        response
      rescue Anthropic::Errors::APIError => e
        if TEMPERATURE_DEPRECATED.match?(e.message) && !@temperature.nil?
          @transcript.record_event("temperature_dropped", model: @config.model)
          @temperature = nil
          attempt -= 1
          retry
        end

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

    def api_failed(final_message) = result(final_message, "api_error")

    def result(final_message, finish_reason)
      Result.new(
        final_message: final_message, finish_reason: finish_reason,
        api_calls: @api_calls, tool_calls: @tool.call_count,
        input_tokens: @usage[:input_tokens], output_tokens: @usage[:output_tokens],
        cache_creation_input_tokens: @usage[:cache_creation_input_tokens],
        cache_read_input_tokens: @usage[:cache_read_input_tokens],
        temperature: @temperature,
        response_model: @response_model
      )
    end

    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
