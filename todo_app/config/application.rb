require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
# require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module TodoApp
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    # request_recorder.rb は experiment.rb から require_relative するので autoload の対象外にする。
    config.autoload_lib(ignore: %w[assets tasks request_recorder.rb exceptions_app.rb])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil

    # 画面の文言、エラーメッセージ、シードは日本語にする。
    config.i18n.default_locale = :ja

    # 実験の条件切り替え用の機能フラグ。
    # アーカイブ「操作」の有無だけを制御する（カラムやバリデーションは常に存在する）。
    config.x.features.archive = ENV["FEATURE_ARCHIVE"] == "1"
    # ToDo のタイトルの文字数上限（100）。モデルの検証と、HTML の maxlength が参照する。
    config.x.features.title_limit = ENV["FEATURE_TITLE_LIMIT"] == "1"

    # 更新（PATCH）の成功応答を 204 No Content にする。作成・完了・アーカイブ・削除には及ばない。
    config.x.responses.update_no_content = ENV["UPDATE_NO_CONTENT"] == "1"

    # 例外時の応答。/api 以下は JSON、それ以外は public/*.html（Rails既定）。
    require_relative "../lib/exceptions_app"
    config.exceptions_app = ExceptionsApp.new(Rails.public_path)
  end
end
