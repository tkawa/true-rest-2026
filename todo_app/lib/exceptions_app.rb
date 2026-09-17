require "json"
require "action_dispatch"

# config.exceptions_app に渡す Rack アプリ。
# ShowExceptions から PATH_INFO="/<status>" で呼ばれる。
# 元のリクエストが /api 以下なら JSON、それ以外は Rails 既定の public/<status>.html を返す。
class ExceptionsApp
  MESSAGES = {
    400 => "リクエストの形式が正しくありません",
    404 => "見つかりません",
    406 => "この形式では応答できません",
    422 => "リクエストを処理できません",
    500 => "サーバ内部でエラーが発生しました"
  }.freeze

  def initialize(public_path)
    @public_exceptions = ActionDispatch::PublicExceptions.new(public_path)
  end

  def call(env)
    request = ActionDispatch::Request.new(env)
    return @public_exceptions.call(env) unless api_request?(request)

    status = request.path_info.delete_prefix("/").to_i
    body = JSON.generate(errors: [ MESSAGES.fetch(status, "エラーが発生しました") ])
    [ status, { "content-type" => "application/json; charset=utf-8", "content-length" => body.bytesize.to_s }, [ body ] ]
  end

  private

  # ShowExceptions は PATH_INFO を /<status> に書き換えるので、元のパスで判定する。
  def api_request?(request)
    original = request.get_header("action_dispatch.original_path") || request.original_fullpath
    original == "/api" || original.start_with?("/api/")
  end
end
