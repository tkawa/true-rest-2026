require "rails_helper"

RSpec.describe "Lists", type: :request do
  let!(:list) { List.create!(name: "テスト用リスト") }

  describe "GET /api/lists" do
    it "アーカイブ済みを含む全リストを返す", openapi: {
      summary: "リスト一覧",
      description: [
        "アーカイブ済みを含むすべてのリストを返します。archived が true のリストにはToDoを追加できません。",
        ("today はサーバの今日の日付（YYYY-MM-DD）で、期限の計算の基準です。" if Rails.configuration.x.api.situated)
      ].compact.join(" ")
    } do
      List.create!(name: "テスト用アーカイブリスト").archive!

      get "/api/lists"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.size).to eq(2)
      expect(response.parsed_body.map { |l| l["archived"] }).to contain_exactly(false, true)
    end
  end

  describe "GET /api/lists/:id" do
    it "ToDoを埋め込んだリストを返す", openapi: {
      summary: "リスト詳細",
      description: [
        "リストと、そのリストに属するToDoをまとめて返します。",
        ("today はサーバの今日の日付（YYYY-MM-DD）で、期限の計算の基準です。" if Rails.configuration.x.api.situated),
        ("overdue は、未完了で期限が今日より前なら true です。" if Rails.configuration.x.api.situated)
      ].compact.join(" ")
    } do
      list.todos.create!(title: "テストToDo")

      get "/api/lists/#{list.id}"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["todos"].size).to eq(1)
    end

    it "存在しないIDなら404を返す", openapi: {
      summary: "リスト詳細",
      description: "指定したIDのリストがない場合は404を返します。"
    } do
      get "/api/lists/999999"

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["errors"]).to eq([ "見つかりません" ])
    end
  end

  describe "POST /api/lists" do
    it "リストを作る", openapi: {
      summary: "リスト作成",
      description: "名前を指定して新しいリストを作ります。作成後のURLは Location ヘッダに入ります。"
    } do
      post "/api/lists", params: { list: { name: "新しいテスト用リスト" } }, as: :json

      expect(response).to have_http_status(:created)
      expect(response.headers["Location"]).to eq("http://www.example.com/api/lists/#{List.last.id}")
      expect(response.parsed_body["name"]).to eq("新しいテスト用リスト")
    end

    it "名前が空なら422を返す", openapi: {
      summary: "リスト作成",
      description: "名前は必須です。空の場合は422を返します。"
    } do
      post "/api/lists", params: { list: { name: "" } }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to be_present
    end
  end

  describe "PATCH /api/lists/:id" do
    it "リスト名を変える", openapi: {
      summary: "リスト名の変更",
      description: OpenapiText.pick(
        full: "リストの名前だけを変更します。アーカイブ状態はこの操作では変わりません。",
        terse: "リストの名前を変更します。"
      )
    } do
      patch "/api/lists/#{list.id}", params: { list: { name: "変更後のテスト用リスト" } }, as: :json

      if Rails.configuration.x.responses.update_no_content
        expect(response).to have_http_status(:no_content)
        expect(response.body).to be_empty
      else
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["name"]).to eq("変更後のテスト用リスト")
      end
      expect(list.reload.name).to eq("変更後のテスト用リスト")
    end

    it "名前が空なら422を返す", openapi: {
      summary: "リスト名の変更",
      description: "名前は必須です。空の場合は422を返します。"
    } do
      patch "/api/lists/#{list.id}", params: { list: { name: "" } }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to be_present
    end
  end

  describe "DELETE /api/lists/:id" do
    it "リストを消す", openapi: {
      summary: "リスト削除",
      description: "リストと、そのリストに属するToDoをまとめて削除します。"
    } do
      delete "/api/lists/#{list.id}"

      expect(response).to have_http_status(:no_content)
      expect(List.exists?(list.id)).to be false
    end
  end
end
