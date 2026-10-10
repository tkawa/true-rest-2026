require "active_support/core_ext/integer/time"

# 環境ファイルは autoload より先に評価されるので、明示的に読み込む。
require_relative "../../lib/request_recorder"
require_relative "../../lib/experiment_clock"

Rails.application.configure do
  # 実験用の環境。本番相当の応答をローカルで出すためのもので、
  # 開発モードの例外ページ（ルーティング一覧を含む）を出さない。

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.enabled = true
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # localhost で平文HTTPのまま動かす。
  config.assume_ssl = false
  config.force_ssl = false

  # 実験専用なので credentials に依存しない固定値でよい。
  config.secret_key_base = ENV.fetch("SECRET_KEY_BASE", "experiment-only-fixed-key")

  # リクエスト記録。EXPERIMENT_LOG が設定されているときだけ書き出す。
  config.middleware.use RequestRecorder

  # EXPERIMENT_TODAY があるときは、サーバの時計そのものを固定の今日の 09:00 起点に合わせる。
  # 書き込み時刻（created_at など）が config.x.today と食い違う世界にならないようにする。
  config.after_initialize do
    ExperimentClock.start(ENV["EXPERIMENT_TODAY"]) if ENV["EXPERIMENT_TODAY"].present?
  end

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)
  config.log_level = :warn

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Enable locale fallbacks for I18n.
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # localhost で動かすので Host ヘッダは制限しない。
  config.hosts.clear
end
