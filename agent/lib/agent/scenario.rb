require "digest"
require "yaml"

module Agent
  # scenarios/*.yml の読み込み。条件の追加が yml の編集だけで済むようにしておく。
  class Scenario
    DEFAULT_DIR = File.expand_path("../../scenarios", __dir__).freeze

    Condition = Struct.new(:name, :spec_version, keyword_init: true)

    attr_reader :id, :name, :instruction, :feature_archive, :conditions, :expected

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
      @expected = data.fetch("expected", {})
      @conditions = data.fetch("conditions").map do |condition_name, settings|
        Condition.new(name: condition_name, spec_version: (settings || {})["spec"])
      end
    end

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
