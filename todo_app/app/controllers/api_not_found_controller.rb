# /api 以下の未定義パスを、HTMLの404ページではなくJSONの404で返す。
class ApiNotFoundController < ApplicationController
  def show
    render json: { errors: [ "見つかりません" ] }, status: :not_found
  end
end
