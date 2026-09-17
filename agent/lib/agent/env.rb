require "dotenv"

module Agent
  # 認証情報と設定は experiment/agent/.env から読む。
  # 既に設定済みの環境変数は上書きしない（シェル側の指定を優先する）。
  module Env
    PATH = File.expand_path("../../.env", __dir__).freeze

    def self.load
      Dotenv.load(PATH) if File.exist?(PATH)
    end
  end
end

Agent::Env.load
