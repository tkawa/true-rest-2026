require "rails_helper"

RSpec.describe "JSON表現のエラー応答", type: :request do
  let!(:list) { List.create!(name: "テスト用リスト") }

  describe "パラメータの包みが無いとき" do
    it "400とJSONのエラー本文を返す", openapi: {
      summary: "リスト名の変更",
      description: "変更する属性は list で包んでください。包みが無い場合は400を返します。"
    } do
      patch "/api/lists/#{list.id}", params: { archived: true }, as: :json

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["errors"]).to eq([ "list パラメータが必要です" ])
    end
  end

  describe "仕様書にないURL" do
    it "404とJSONのエラー本文を返す" do
      get "/api/does-not-exist"

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["errors"]).to eq([ "見つかりません" ])
      expect(response.media_type).to eq("application/json")
    end

    it "/api そのものも404とJSONで返す" do
      get "/api"

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["errors"]).to eq([ "見つかりません" ])
    end
  end
end
