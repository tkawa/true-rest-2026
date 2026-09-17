# 仕様書に埋め込まれる example を決定的にするため、request spec は時刻を固定する。
RSpec.configure do |config|
  config.include ActiveSupport::Testing::TimeHelpers

  config.around(:each, type: :request) do |example|
    travel_to(Time.utc(2026, 1, 1)) { example.run }
  end
end
