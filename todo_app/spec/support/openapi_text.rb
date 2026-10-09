# 仕様書の文体。terse は「この操作では変わりません」型の警告文を持たない。
module OpenapiText
  STYLE = ENV.fetch("OPENAPI_STYLE", "full").freeze
  abort "OPENAPI_STYLE は full か terse（指定値: #{STYLE}）" unless %w[full terse].include?(STYLE)

  def self.terse? = STYLE == "terse"

  def self.pick(full:, terse:) = terse? ? terse : full
end
