require "rails_helper"

# JSON表現の例外応答は config.exceptions_app（ExceptionsApp）が組み立てる。
# 仕様書に載せる「操作」ではないので、いずれの example も記録しない。
RSpec.describe "JSON表現の例外応答", type: :request do
  let!(:list) { List.create!(name: "テスト用リスト") }

  describe "パラメータの包みが無いとき" do
    it "400とJSONのエラー本文を返す", openapi: false do
      patch "/api/lists/#{list.id}", params: { archived: true }, as: :json

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["errors"]).to eq([ "リクエストの形式が正しくありません" ])
      expect(response.media_type).to eq("application/json")
    end
  end

  describe "仕様書にないURL" do
    it "404とJSONのエラー本文を返す", openapi: false do
      get "/api/foo"

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["errors"]).to eq([ "見つかりません" ])
      expect(response.media_type).to eq("application/json")
    end

    it "/api そのものも404とJSONで返す", openapi: false do
      get "/api"

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["errors"]).to eq([ "見つかりません" ])
    end
  end

  describe "存在しないIDのとき" do
    it "404とJSONのエラー本文を返す", openapi: false do
      get "/api/lists/999999"

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["errors"]).to eq([ "見つかりません" ])
    end
  end
end
