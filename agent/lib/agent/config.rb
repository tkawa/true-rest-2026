module Agent
  Config = Struct.new(
    :model, :temperature, :max_tool_calls, :timeout_seconds, :port, :agent_name,
    keyword_init: true
  ) do
    DEFAULT_MODEL = "claude-sonnet-5".freeze

    def self.default(**overrides)
      new(
        model: ENV.fetch("MODEL", DEFAULT_MODEL),
        temperature: 0,
        max_tool_calls: Integer(ENV.fetch("MAX_TOOL_CALLS", 25)),
        timeout_seconds: Integer(ENV.fetch("RUN_TIMEOUT_SECONDS", 600)),
        port: Integer(ENV.fetch("PORT", 3000)),
        agent_name: "loop"
      ).tap { |config| overrides.each { |key, value| config[key] = value } }
    end
  end
end
