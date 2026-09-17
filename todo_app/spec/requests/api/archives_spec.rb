require "rails_helper"

# アーカイブ操作は機能フラグ FEATURE_ARCHIVE=1 のときだけ存在する。
RSpec.describe "Archives", type: :request, if: Rails.configuration.x.features.archive do
  let!(:list) { List.create!(name: "テスト用リスト") }

  describe "POST /api/lists/:list_id/archive" do
    it "リストをアーカイブする", openapi: {
      summary: "リストをアーカイブする",
      description: "リストをアーカイブします。アーカイブ済みのリストにはToDoを追加できません。"
    } do
      post "/api/lists/#{list.id}/archive"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["archived"]).to be true
    end

    it "存在しないリストなら404を返す", openapi: {
      summary: "リストをアーカイブする",
      description: "指定したIDのリストがない場合は404を返します。"
    } do
      post "/api/lists/999999/archive"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/lists/:list_id/archive" do
    it "アーカイブを解除する", openapi: {
      summary: "リストのアーカイブを解除する",
      description: "アーカイブ済みのリストを現行に戻します。解除するとToDoを追加できるようになります。"
    } do
      list.archive!

      delete "/api/lists/#{list.id}/archive"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["archived"]).to be false
    end
  end
end
