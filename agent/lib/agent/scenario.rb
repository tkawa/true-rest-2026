require "digest"
require "yaml"

module Agent
  # scenarios/*.yml の読み込み。条件の追加が yml の編集だけで済むようにしておく。
  class Scenario
    DEFAULT_DIR = File.expand_path("../../scenarios", __dir__).freeze

    # 条件ごとにサーバへ渡せる環境変数。フラグの意味が yml に散らばらないよう、キーを限定する。
    ALLOWED_SERVER_ENV_KEYS = %w[UPDATE_NO_CONTENT].freeze

    Condition = Struct.new(:name, :spec_version, :server_env, keyword_init: true)

    attr_reader :id, :name, :instruction, :feature_archive, :feature_title_limit, :conditions, :expected

    def self.dir = ENV.fetch("SCENARIO_DIR", DEFAULT_DIR)

    def self.load(id, dir: self.dir)
      path = File.join(dir, "#{id}.yml")
      raise ArgumentError, "シナリオが見つかりません: #{id}" unless File.exist?(path)

      from_file(path)
    end

    def self.all(dir: self.dir)
      Dir.glob(File.join(dir, "*.yml")).sort.map { |path| from_file(path) }
    end

    def self.from_file(path)
      source = File.read(path)
      new(YAML.safe_load(source), source: source)
    end

    # 指示文を変えたら値が変わる。どの版で回した実行かを記録に残すため。
    def sha256 = Digest::SHA256.hexdigest(@source.to_s)

    def initialize(data, source: nil)
      @source = source
      @id = data.fetch("id")
      @name = data.fetch("name")
      @instruction = data.fetch("instruction")
      @feature_archive = data.fetch("feature_archive", false)
      @feature_title_limit = data.fetch("feature_title_limit", false)
      @expected = data.fetch("expected", {})
      @conditions = data.fetch("conditions").map do |condition_name, settings|
        settings ||= {}
        Condition.new(
          name: condition_name, spec_version: settings["spec"],
          server_env: validate_server_env(condition_name, settings.fetch("server_env", {}))
        )
      end
    end

    def validate_server_env(condition_name, server_env)
      server_env = (server_env || {}).to_h { |key, value| [ key.to_s, value.to_s ] }
      unknown = server_env.keys - ALLOWED_SERVER_ENV_KEYS
      unless unknown.empty?
        raise ArgumentError,
              "シナリオ #{id} の条件 #{condition_name} の server_env に指定できないキー: #{unknown.join(', ')}" \
              "（指定できるのは #{ALLOWED_SERVER_ENV_KEYS.join(', ')} のみ）"
      end
      server_env.freeze
    end
    private :validate_server_env

    def condition(name)
      conditions.find { |c| c.name == name } ||
        raise(ArgumentError, "シナリオ #{id} に条件 #{name} はありません")
    end

    def condition_names = conditions.map(&:name)

    def expected_changes = expected.fetch("changes", [])

    def expected_claim = expected["claim"]

    def final_message_includes = expected.fetch("final_message_includes", [])
  end
end
