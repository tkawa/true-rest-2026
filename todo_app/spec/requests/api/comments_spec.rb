require "rails_helper"

# コメントの経路は FEATURE_COMMENTS=1 のときだけある。仕様書は openapi-v1-comments*.yaml に出る。
RSpec.describe "Comments", type: :request, if: Rails.configuration.x.features.comments do
  let!(:list) { List.create!(name: "テスト用リスト") }
  let!(:todo) { list.todos.create!(title: "テストToDo") }

  describe "GET /api/todos/:todo_id/comments" do
    it "ToDoに付いたコメントを古い順に返す", openapi: {
      summary: "コメント一覧",
      description: "ToDoに付いたコメントを古い順に返します。"
    } do
      todo.comments.create!(body: "最初のコメント")
      todo.comments.create!(body: "次のコメント")

      get "/api/todos/#{todo.id}/comments"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.map { |c| c["body"] }).to eq(%w[最初のコメント 次のコメント])
    end

    it "存在しないToDoなら404を返す", openapi: {
      summary: "コメント一覧",
      description: "指定したIDのToDoがない場合は404を返します。"
    } do
      get "/api/todos/999999/comments"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/todos/:todo_id/comments" do
    it "コメントを追加する", openapi: {
      summary: "コメント追加",
      description: "ToDoにコメントを追加します。body は必須です。"
    } do
      post "/api/todos/#{todo.id}/comments", params: { comment: { body: "追加したコメント" } }, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["body"]).to eq("追加したコメント")
      expect(todo.comments.count).to eq(1)
    end

    it "body が空なら422を返す", openapi: {
      summary: "コメント追加",
      description: "body は必須です。空の場合は422を返します。"
    } do
      post "/api/todos/#{todo.id}/comments", params: { comment: { body: "" } }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to be_present
    end

    it "存在しないToDoなら404を返す", openapi: {
      summary: "コメント追加",
      description: "指定したIDのToDoがない場合は404を返します。"
    } do
      post "/api/todos/999999/comments", params: { comment: { body: "追加したコメント" } }, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/todos/:id" do
    it "ToDoを消すとコメントも消える", openapi: false do
      todo.comments.create!(body: "消えるコメント")

      delete "/api/todos/#{todo.id}"

      expect(response).to have_http_status(:no_content)
      expect(Comment.count).to eq(0)
    end
  end
end
