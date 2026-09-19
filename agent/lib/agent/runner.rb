require "fileutils"
require "json"
require "sqlite3"
require "time"

require "agent/http_tool"
require "agent/initial_message"
require "agent/oracle"
require "agent/scenario"
require "agent/server"
require "agent/transcript"

module Agent
  # 1回の実行。毎回スナップショットから始め、終了後にDB差分で判定する。
  class Runner
    AGENT_ROOT = File.expand_path("../..", __dir__).freeze
    TODO_APP_DIR = File.expand_path("../todo_app", AGENT_ROOT).freeze
    def initialize(scenario:, condition_name:, config:, agent_factory:, build_initial_message: true)
      @scenario = scenario
      @condition = scenario.condition(condition_name)
      @config = config
      @agent_factory = agent_factory
      @build_initial_message = build_initial_message
    end

    def call(sequence: 1)
      run_id, dir = reserve_directory(sequence)

      database_path = File.join(dir, "db.sqlite3")
      FileUtils.cp(seed_path, database_path)

      server = Server.new(
        app_dir: TODO_APP_DIR, port: @config.port, database_path: database_path,
        log_path: File.join(dir, "requests.jsonl"), server_log_path: File.join(dir, "server.log"),
        feature_archive: @scenario.feature_archive
      )

      started_at = Time.now.utc
      transcript = Transcript.new(File.join(dir, "transcript.jsonl"))
      begin
        server.start
        result = run_agent(server, dir, transcript)
      ensure
        transcript.close
        server.stop
        checkpoint(database_path)
      end

      write_run_json(dir, run_id, started_at, result, database_path)
    end

    private

    def seed_path = File.join(TODO_APP_DIR, "db", "seed.sqlite3")

    # WAL を本体に畳み込み、db.sqlite3 単体で実行後の状態を表すようにする。
    def checkpoint(path)
      db = SQLite3::Database.new(path)
      db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
      db.close
      FileUtils.rm_f([ "#{path}-wal", "#{path}-shm" ])
    rescue StandardError
      nil
    end

    # 同じ秒に始まった実行が同じディレクトリを共有しないよう、
    # 空いている連番が見つかるまで進める。
    def reserve_directory(sequence)
      stamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
      parent = File.join(@config.runs_dir, @scenario.id, @condition.name)
      FileUtils.mkdir_p(parent)

      loop do
        run_id = format("%s-%s-%s-%03d", @scenario.id, @condition.name, stamp, sequence)
        dir = File.join(parent, run_id)
        begin
          Dir.mkdir(dir)
          return [ run_id, dir ]
        rescue Errno::EEXIST
          sequence += 1
        end
      end
    end

    def run_agent(server, dir, transcript)
      tool = HttpTool.new(allowed_origin: server.origin)
      message = nil
      if @build_initial_message
        message = InitialMessage.new(app_dir: TODO_APP_DIR, origin: server.origin)
                                .build(@scenario.instruction, @condition)
        File.write(File.join(dir, "initial_message.md"), message)
        transcript.record_event("initial_message", condition: @condition.name, content: message)
      end

      agent = @agent_factory.call(
        scenario: @scenario, condition: @condition, http_tool: tool, origin: server.origin,
        transcript: transcript, initial_message: message, config: @config, run_dir: dir
      )
      started = monotonic
      outcome = agent.run
      [ outcome, tool, ((monotonic - started) * 1000).round ]
    end

    def write_run_json(dir, run_id, started_at, (outcome, tool, wall_time_ms), database_path)
      requests_path = File.join(dir, "requests.jsonl")
      verdict = Oracle.new(
        scenario: @scenario, condition: @condition.name,
        seed_path: seed_path, result_path: database_path,
        final_message: outcome.final_message, finish_reason: outcome.finish_reason,
        requests_path: requests_path
      ).call

      data = {
        "run_id" => run_id,
        "scenario" => @scenario.id,
        "scenario_name" => @scenario.name,
        "condition" => @condition.name,
        "spec_version" => @condition.spec_version,
        "feature_archive" => @scenario.feature_archive,
        "agent" => @config.agent_name,
        "model" => @config.model,
        "response_model" => outcome.respond_to?(:response_model) ? outcome.response_model : nil,
        "temperature" => effective_temperature(outcome),
        "max_tool_calls" => @config.max_tool_calls,
        "harness_git_commit" => git_commit(AGENT_ROOT),
        "todo_app_git_commit" => git_commit(TODO_APP_DIR),
        "started_at" => started_at.iso8601,
        "wall_time_ms" => wall_time_ms,
        "finish_reason" => outcome.finish_reason,
        "final_message" => outcome.final_message,
        "api_calls" => outcome.api_calls,
        "tool_calls" => outcome.tool_calls,
        "input_tokens" => outcome.input_tokens,
        "output_tokens" => outcome.output_tokens,
        "cache_creation_input_tokens" => outcome.cache_creation_input_tokens,
        "cache_read_input_tokens" => outcome.cache_read_input_tokens,
        "tool_call_log" => tool.calls.map { |c| c.to_h.transform_keys(&:to_s) }
      }.merge(extra_of(outcome)).merge(server_metrics(requests_path)).merge(verdict.to_h)

      File.write(File.join(dir, "run.json"), JSON.pretty_generate(data) + "\n")
      data
    end

    # 送らなかった場合は null を残す（モデルが受け付けないとき）。
    def effective_temperature(outcome)
      outcome.respond_to?(:temperature) ? outcome.temperature : @config.temperature
    end

    # 参考実行だけが持つ値（CLIのバージョン、ターン数など）。
    def extra_of(outcome)
      outcome.respond_to?(:extra) ? outcome.extra.to_h : {}
    end

    # リクエスト数とエラー数はサーバ側の記録から取る。エージェントの自己申告には依存しない。
    def server_metrics(path)
      return empty_metrics unless File.exist?(path)

      entries = File.readlines(path).map { |line| JSON.parse(line) }
      statuses = entries.map { |entry| entry["status"].to_i }
      {
        "http_requests" => entries.size,
        "error_responses" => statuses.count { |s| s >= 400 },
        "error_responses_by_status" => statuses.select { |s| s >= 400 }.tally.transform_keys(&:to_s),
        "redirects" => statuses.count { |s| (300..399).cover?(s) },
        "response_bytes_total" => entries.sum { |entry| entry["response_bytes"].to_i }
      }
    rescue JSON::ParserError
      empty_metrics
    end

    def empty_metrics
      {
        "http_requests" => 0, "error_responses" => 0, "error_responses_by_status" => {},
        "redirects" => 0, "response_bytes_total" => 0
      }
    end

    def git_commit(dir)
      out = IO.popen(%w[git --no-optional-locks rev-parse HEAD], chdir: dir, err: File::NULL, &:read)
      $?&.success? ? out.strip : nil
    rescue StandardError
      nil
    end

    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
