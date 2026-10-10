require "rspec/openapi"
require_relative "openapi_text"

# 仕様書は手で書かず、request spec の実行結果から生成する。
# 出力先は機能フラグで分ける（OFF: v1、ON: v2）。
# ファイル名は doc/openapi-<line>[-terse][-nocontent][-titlelimit][-due][-situated].yaml。
RSpec::OpenAPI.path = ENV.fetch("OPENAPI_PATH") do
  line = Rails.configuration.x.features.archive ? "v2" : "v1"
  suffix = [
    (OpenapiText.terse? ? "terse" : nil),
    (Rails.configuration.x.responses.update_no_content ? "nocontent" : nil),
    (Rails.configuration.x.features.title_limit ? "titlelimit" : nil),
    (Rails.configuration.x.features.due ? "due" : nil),
    (Rails.configuration.x.api.situated ? "situated" : nil)
  ].compact
  "doc/openapi-#{[ line, *suffix ].join('-')}.yaml"
end

RSpec::OpenAPI.title = "ToDo API"
# エージェントには /api 以下だけを渡すので、servers に /api まで含めて
# パスからは取り除く（post_process_hook で実施）。
RSpec::OpenAPI.servers = [ { url: "http://localhost:3000/api" } ]

RSpec::OpenAPI.summary_builder = ->(example) { example.metadata.dig(:openapi, :summary) }
RSpec::OpenAPI.description_builder = ->(example) { example.metadata.dig(:openapi, :description) }

RSpec::OpenAPI.post_process_hook = lambda do |_path, _records, spec|
  paths = spec["paths"] || spec[:paths]
  next if paths.nil?

  paths.keys.each do |key|
    next unless key.to_s.start_with?("/api/")

    paths[key.to_s.delete_prefix("/api")] = paths.delete(key)
  end
end
