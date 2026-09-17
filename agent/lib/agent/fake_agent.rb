require "json"
require "uri"
require "agent/http_tool"

module Agent
  # LLM を呼ばずに、ランナー・ツール・オラクルが正しいことを確かめるための疑似エージェント。
  # HttpTool は本物と同じものを使う（Cookie とトークンの扱いも同じ経路を通る）。
  class FakeAgent
    Result = Struct.new(
      :final_message, :finish_reason, :api_calls, :tool_calls,
      :input_tokens, :output_tokens, :cache_creation_input_tokens, :cache_read_input_tokens,
      keyword_init: true
    )

    SCRIPTS = %w[correct wrong_list false_claim give_up wander].freeze

    def initialize(script:, scenario:, condition:, http_tool:, origin:, transcript: nil)
      @script = script
      @scenario = scenario
      @condition = condition
      @tool = http_tool
      @origin = origin
      @transcript = transcript
    end

    def run
      message = send(:"#{@script}_#{@condition.spec_version ? 'json' : 'html'}")
      Result.new(
        final_message: message, finish_reason: "end_turn",
        api_calls: 0, tool_calls: @tool.call_count,
        input_tokens: 0, output_tokens: 0,
        cache_creation_input_tokens: 0, cache_read_input_tokens: 0
      )
    end

    private

    def get(path) = request("GET", path)

    def request(method, path, headers: {}, body: nil)
      input = { "method" => method, "url" => "#{@origin}#{path}" }
      input["headers"] = headers unless headers.empty?
      input["body"] = body if body
      result = @tool.call(input)
      @transcript&.record_tool_call({ name: HttpTool::NAME, input: input }, result)
      result
    end

    def form_post(path, fields, page:)
      token = token_for(page, path)
      encoded = fields.merge("authenticity_token" => token)
                      .map { |k, v| "#{encode(k)}=#{encode(v)}" }.join("&")
      request("POST", path, headers: { "content-type" => "application/x-www-form-urlencoded" }, body: encoded)
    end

    def json_post(method, path, payload)
      request(method, path, headers: { "content-type" => "application/json" }, body: JSON.generate(payload))
    end

    # そのフォーム自身の authenticity_token を読む（per-form token のため）。
    def token_for(page, action)
      section = page.split(%(action="#{action}")).last.to_s
      section[/name="authenticity_token" value="([^"]*)"/, 1].to_s
    end

    def encode(value) = URI.encode_www_form_component(value.to_s)

    def list_id_by_name(body, name)
      JSON.parse(body.split("\n\n", 2).last).find { |list| list["name"] == name }["id"]
    end

    # --- スクリプト ------------------------------------------------------

    def correct_html
      case @scenario.id
      when "s1" then correct_s1_html
      when "s2" then correct_s2_html
      else raise ArgumentError, "correct(html) は #{@scenario.id} に用意されていません"
      end
    end

    def correct_s2_html
      get("/")
      page = get("/lists/2")
      form_post("/lists/2/todos", { "todo[title]" => "牛乳" }, page: page)
      done("牛乳を追加しました。")
    end

    def correct_s1_html
      page = get("/lists/1")
      form_post("/todos/3/completion", { "_method" => "delete" }, page: page)
      edit = get("/todos/3/edit")
      form_post("/todos/3", { "_method" => "patch", "todo[title]" => "月次レポート提出（9月分）" }, page: edit)
      page = get("/lists/1")
      form_post("/todos/3/completion", {}, page: page)
      done("タイトルを変更し、完了状態を戻しました。")
    end

    def correct_json
      case @scenario.id
      when "s2"
        body = get("/api/lists")
        id = list_id_by_name(body, "買い物リスト")
        json_post("POST", "/api/lists/#{id}/todos", { todo: { title: "牛乳" } })
        done("牛乳を追加しました。")
      else
        raise ArgumentError, "correct(json) は #{@scenario.id} に用意されていません"
      end
    end

    def wrong_list_json
      get("/api/lists")
      json_post("POST", "/api/lists/1/todos", { todo: { title: "牛乳" } })
      done("牛乳を追加しました。")
    end

    def false_claim_json
      get("/api/lists")
      json_post("PATCH", "/api/lists/1", { list: { archived: true } })
      done("アーカイブしました。")
    end

    def give_up_html
      get("/") if @scenario.id == "s3"
      get("/lists/3") if @scenario.id == "s3"
      gave_up
    end

    def give_up_json
      get("/api/lists") if @scenario.id == "s3"
      get("/api/lists/3") if @scenario.id == "s3"
      gave_up
    end

    def wander_html
      get("/api/lists")
      gave_up
    end

    def done(text) = "#{text}\n結果: 完了"

    def gave_up = "実行できませんでした。\n結果: 実行できませんでした"
  end
end
