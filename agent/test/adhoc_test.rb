require "test_helper"
require "json"
require "agent/adhoc"
require "agent/config"
require "agent/fake_agent"
require "agent/scenario"
require "agent/server"

class AdhocTest < Minitest::Test
  PORT = Integer(ENV.fetch("ADHOC_TEST_PORT", 3011))
  RUNS_DIR = File.expand_path("../../runs", __dir__).freeze

  def setup
    @dir = Dir.mktmpdir("adhoc-test")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def entry_for_url(url) = Agent::Adhoc::Entry.new(url: url)

  def entry_for_spec(body, path: "/tmp/openapi.yaml")
    Agent::Adhoc::Entry.new(spec_path: path, spec_body: body)
  end

  def build(entry, task: "買い物リストに牛乳を追加して", **options)
    Agent::Adhoc.new(entry: entry, task: task, config: Agent::Config.default, out_dir: @dir, **options)
  end

  # 実験の記録に残っている初期メッセージと、同じ入力で組み立てたものを突き合わせる。
  def recorded_message(condition)
    path = Dir.glob(File.join(RUNS_DIR, "s2", condition, "*", "initial_message.md")).sort.first
    skip("実験の記録が見つかりません: s2/#{condition}") if path.nil?
    File.read(path)
  end

  def test_the_url_message_matches_the_experiment
    recorded = recorded_message("html")
    origin = recorded[%r{操作対象: (\S+)}, 1]

    assert_equal recorded, build(entry_for_url(origin)).initial_message
  end

  def test_the_spec_message_matches_the_experiment
    recorded = recorded_message("json")
    body = recorded[/```yaml\n(.*)\n```\n\z/m, 1]

    assert_equal recorded, build(entry_for_spec(body)).initial_message
  end

  def test_the_origin_comes_from_the_url
    assert_equal "http://localhost:3000", build(entry_for_url("http://localhost:3000/lists")).origin
    assert_equal "https://example.com:443", build(entry_for_url("https://example.com/")).origin
  end

  def test_the_origin_comes_from_the_first_server_in_the_spec
    spec = "openapi: 3.0.0\nservers:\n- url: http://localhost:4567/api\n"

    assert_equal "http://localhost:4567", build(entry_for_spec(spec)).origin
  end

  def test_the_origin_option_wins
    spec = "openapi: 3.0.0\nservers:\n- url: http://localhost:4567/api\n"

    assert_equal "http://example.test:80", build(entry_for_spec(spec), origin: "http://example.test").origin
  end

  def test_a_relative_server_url_is_an_error
    spec = "openapi: 3.0.0\nservers:\n- url: /api\n"

    error = assert_raises(Agent::Adhoc::Error) { build(entry_for_spec(spec)) }

    assert_match(/--origin/, error.message)
  end

  def test_the_spec_body_is_not_rewritten
    spec = "openapi: 3.0.0\nservers:\n- url: http://localhost:4567/api\n"

    assert_includes build(entry_for_spec(spec)).initial_message, "http://localhost:4567/api"
  end

  # --- 固定ヘッダ -----------------------------------------------------

  def header_of(tool, name)
    uri = URI.parse("http://localhost:3000/")
    tool.send(:build_request, "GET", uri, {}, nil)[name]
  end

  def test_fixed_headers_are_added
    tool = Agent::HttpTool.new(allowed_origin: "http://localhost:3000",
                               default_headers: { "Authorization" => "Bearer fixed" })

    assert_equal "Bearer fixed", header_of(tool, "authorization")
  end

  def test_the_agent_overrides_a_fixed_header
    tool = Agent::HttpTool.new(allowed_origin: "http://localhost:3000",
                               default_headers: { "Authorization" => "Bearer fixed" })
    uri = URI.parse("http://localhost:3000/")

    request = tool.send(:build_request, "GET", uri, { "Authorization" => "Bearer agent" }, nil)

    assert_equal "Bearer agent", request["authorization"]
  end

  def test_the_cookie_jar_wins_over_a_fixed_cookie_header
    jar = Agent::CookieJar.new
    jar.store([ "session=from-jar; path=/" ])
    tool = Agent::HttpTool.new(allowed_origin: "http://localhost:3000", cookie_jar: jar,
                               default_headers: { "Cookie" => "session=fixed" })

    assert_equal "session=from-jar", header_of(tool, "cookie")
  end

  def test_no_fixed_headers_means_no_change
    tool = Agent::HttpTool.new(allowed_origin: "http://localhost:3000")

    assert_nil header_of(tool, "authorization")
  end

  # --- 秘匿 -----------------------------------------------------------

  def test_secret_header_values_are_redacted_in_records
    headers = { "Authorization" => "Bearer x", "Cookie" => "a=b", "X-Api-Key" => "k",
                "Content-Type" => "application/json" }

    safe = Agent::Reference::Sanitizer.headers(headers)

    assert_equal "<REDACTED>", safe["Authorization"]
    assert_equal "<REDACTED>", safe["Cookie"]
    assert_equal "<REDACTED>", safe["X-Api-Key"]
    assert_equal "application/json", safe["Content-Type"]
  end

  def test_the_spec_is_fingerprinted
    entry = entry_for_spec("openapi: 3.0.0\nservers:\n- url: http://x.test/\n")

    assert_equal Digest::SHA256.hexdigest(entry.spec_body), entry.spec_sha256
  end

  # --- 通し -----------------------------------------------------------

  def with_server
    db = File.join(@dir, "db.sqlite3")
    FileUtils.cp(SEED_DB, db)
    server = Agent::Server.new(
      app_dir: TODO_APP_DIR, port: PORT, database_path: db,
      log_path: File.join(@dir, "requests.jsonl"), server_log_path: File.join(@dir, "server.log")
    ).start
    yield server
  ensure
    server&.stop
  end

  def run_fake(script, entry, headers: {})
    factory = lambda do |tool:, transcript:, initial_message:|
      Agent::FakeAgent.new(
        script: script, scenario: Agent::Scenario.load("s2"),
        condition: entry.spec? ? Agent::Scenario::Condition.new(name: "json", spec_version: "v1")
                               : Agent::Scenario::Condition.new(name: "html"),
        http_tool: tool, origin: "http://localhost:#{PORT}", transcript: transcript
      )
    end
    build(entry, headers: headers).call(agent_factory: factory)
  end

  def test_a_run_through_the_entry_point_records_everything
    with_server do
      data = run_fake("correct", entry_for_url("http://localhost:#{PORT}/"))

      assert_equal 3, data["client_side_requests"]
      assert_equal "完了", data["claim"]
      assert_equal "http://localhost:#{PORT}", data["origin"]
      assert_equal 64, data["system_prompt_sha256"].length
      %w[run.json transcript.jsonl initial_message.md].each do |name|
        assert_path_exists File.join(@dir, name)
      end
    end
  end

  def test_fixed_header_values_never_reach_the_records
    with_server do
      data = run_fake("authenticated", entry_for_url("http://localhost:#{PORT}/"),
                      headers: { "Authorization" => "Bearer fixed-secret" })

      assert_equal [ "Authorization" ], data["fixed_header_names"]
      recorded = File.read(File.join(@dir, "run.json")) + File.read(File.join(@dir, "transcript.jsonl"))
      refute_includes recorded, "fixed-secret"
      refute_includes recorded, "agent-secret"
      assert_includes recorded, "<REDACTED>"
    end
  end
end
