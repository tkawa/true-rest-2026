class ApplicationController < ActionController::Base
  rescue_from ActiveRecord::RecordNotFound do
    respond_to do |format|
      format.html { render file: Rails.public_path.join("404.html"), status: :not_found, layout: false }
      format.json { render json: { errors: [ "見つかりません" ] }, status: :not_found }
    end
  end
end
