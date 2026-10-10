require "fileutils"
require "net/http"
require "socket"

module Agent
  # 実験対象の Rails アプリを、実行ごとに初期状態から起動する。
  # アプリのコードは読み込まず、bin/rails を別プロセスで動かすだけ。
  class Server
    BOOT_TIMEOUT_SECONDS = 30
    STOP_TIMEOUT_SECONDS = 15

    attr_reader :port

    def initialize(app_dir:, port:, database_path:, log_path:, server_log_path:, feature_archive: false,
                   feature_title_limit: false, feature_due: false, today: nil, extra_env: {})
      @app_dir = File.expand_path(app_dir)
      @port = port
      @database_path = File.expand_path(database_path)
      @log_path = File.expand_path(log_path)
      @server_log_path = File.expand_path(server_log_path)
      @feature_archive = feature_archive
      @feature_title_limit = feature_title_limit
      @feature_due = feature_due
      @today = today
      @extra_env = extra_env || {}
      @pid = nil
    end

    def origin = "http://localhost:#{@port}"

    def start
      wait_for_port_release
      FileUtils.mkdir_p(File.dirname(@server_log_path))

      @pid = Process.spawn(
        env, "bin/rails", "s", "-e", "experiment", "-p", @port.to_s,
        chdir: @app_dir, out: [ @server_log_path, "w" ], err: [ :child, :out ], pgroup: true
      )
      wait_until_up
      self
    end

    def stop
      return if @pid.nil?

      terminate(@pid)
      @pid = nil
      wait_for_port_release
    end

    def running?
      return false if @pid.nil?

      Process.waitpid(@pid, Process::WNOHANG).nil?
    rescue Errno::ECHILD
      false
    end

    # テストから、起動時に渡す環境変数を確かめるために公開する。
    def env = build_env

    private

    # ハーネス側の Bundler 環境を子プロセスに持ち込むと、
    # アプリが自分の Gemfile ではなくこちらの Gemfile を読んでしまう。
    def build_env
      unbundled.merge(
        "RAILS_ENV" => "experiment",
        "EXPERIMENT_DB" => @database_path,
        "EXPERIMENT_LOG" => @log_path,
        "SECRET_KEY_BASE" => "x",
        "LANG" => ENV.fetch("LANG", "C.UTF-8")
      ).tap do |e|
        e["FEATURE_ARCHIVE"] = "1" if @feature_archive
        e["FEATURE_TITLE_LIMIT"] = "1" if @feature_title_limit
        e["FEATURE_DUE"] = "1" if @feature_due
        e["EXPERIMENT_TODAY"] = @today.to_s if @today
      end.merge(@extra_env)
    end

    def unbundled
      return {} unless defined?(Bundler)

      cleaned = Bundler.unbundled_env
      removed = (ENV.keys - cleaned.keys).to_h { |key| [ key, nil ] }
      cleaned.merge(removed)
    end

    def wait_until_up
      deadline = now + BOOT_TIMEOUT_SECONDS
      loop do
        return if health_ok?
        raise "サーバが起動しませんでした（#{@server_log_path} を確認してください）" if now > deadline || !running?

        sleep 0.2
      end
    end

    def health_ok?
      response = Net::HTTP.start("localhost", @port, open_timeout: 1, read_timeout: 2) do |http|
        http.get("/up")
      end
      response.code.to_i == 200
    rescue StandardError
      false
    end

    def terminate(pid)
      group = Process.getpgid(pid)
      Process.kill("TERM", -group)
      deadline = now + STOP_TIMEOUT_SECONDS
      loop do
        break if Process.waitpid(pid, Process::WNOHANG)
        if now > deadline
          Process.kill("KILL", -group)
          Process.waitpid(pid)
          break
        end
        sleep 0.1
      end
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end

    def wait_for_port_release
      deadline = now + STOP_TIMEOUT_SECONDS
      loop do
        return unless port_in_use?
        raise "ポート #{@port} が解放されません" if now > deadline

        sleep 0.2
      end
    end

    def port_in_use?
      TCPSocket.new("localhost", @port).close
      true
    rescue StandardError
      false
    end

    def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
