class ApplicationController < ActionController::Base
  # HTML表現ではRails標準のCSRF保護をそのまま残す。
  # JSON表現はフォームを持たず、エージェントはトークンを得る手段がないので対象外にする。
  protect_from_forgery with: :exception, unless: -> { request.format.json? }
end
