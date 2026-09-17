class ApplicationController < ActionController::Base
  # HTML表現ではRails標準のCSRF保護をそのまま残す。
  # JSON表現はフォームを持たず、エージェントはトークンを得る手段がないので対象外にする。
  protect_from_forgery with: :exception, unless: -> { request.format.json? }

  rescue_from ActiveRecord::RecordNotFound do
    respond_to do |format|
      format.html { render file: Rails.public_path.join("404.html"), status: :not_found, layout: false }
      format.json { render json: { errors: [ "見つかりません" ] }, status: :not_found }
    end
  end
end
