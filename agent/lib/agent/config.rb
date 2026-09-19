module Agent
  Config = Struct.new(
    :model, :temperature, :max_tool_calls, :timeout_seconds, :port, :agent_name, :runs_dir,
    keyword_init: true
  ) do
    DEFAULT_MODEL = "claude-sonnet-5".freeze
    DEFAULT_RUNS_DIR = File.expand_path("../../../runs", __dir__).freeze

    def self.default(**overrides)
      new(
        model: ENV.fetch("MODEL", DEFAULT_MODEL),
        temperature: 0,
        max_tool_calls: Integer(ENV.fetch("MAX_TOOL_CALLS", 25)),
        timeout_seconds: Integer(ENV.fetch("RUN_TIMEOUT_SECONDS", 600)),
        port: Integer(ENV.fetch("PORT", 3000)),
        agent_name: "loop",
        runs_dir: ENV.fetch("RUNS_DIR", DEFAULT_RUNS_DIR)
      ).tap { |config| overrides.each { |key, value| config[key] = value } }
    end
  end
end
