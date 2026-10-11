require "rails_helper"

# サブタスクの経路は FEATURE_SUBTASKS=1 のときだけある。仕様書は openapi-v1-subtasks*.yaml に出る。
RSpec.describe "Subtasks", type: :request, if: Rails.configuration.x.features.subtasks do
  let!(:list) { List.create!(name: "テスト用リスト") }
  let!(:todo) { list.todos.create!(title: "テストToDo") }
  let!(:subtask) { todo.subtasks.create!(title: "テストサブタスク") }

  describe "GET /api/todos/:todo_id/subtasks" do
    it "ToDoのサブタスクをid順に返す", openapi: {
      summary: "サブタスク一覧",
      description: "ToDoのサブタスクをid順に返します。completed は完了済みかどうかを表します。"
    } do
      todo.subtasks.create!(title: "二つ目のサブタスク")

      get "/api/todos/#{todo.id}/subtasks"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.map { |s| s["title"] }).to eq(%w[テストサブタスク 二つ目のサブタスク])
    end

    it "存在しないToDoなら404を返す", openapi: {
      summary: "サブタスク一覧",
      description: "指定したIDのToDoがない場合は404を返します。"
    } do
      get "/api/todos/999999/subtasks"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/todos/:todo_id/subtasks" do
    it "サブタスクを追加する", openapi: {
      summary: "サブタスク追加",
      description: "ToDoにサブタスクを追加します。title は必須です。"
    } do
      post "/api/todos/#{todo.id}/subtasks", params: { subtask: { title: "追加したサブタスク" } }, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["completed"]).to be false
    end

    it "title が空なら422を返す", openapi: {
      summary: "サブタスク追加",
      description: "title は必須です。空の場合は422を返します。"
    } do
      post "/api/todos/#{todo.id}/subtasks", params: { subtask: { title: "" } }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "POST /api/subtasks/:subtask_id/completion" do
    it "サブタスクを完了にする", openapi: {
      summary: "サブタスクを完了にする",
      description: "サブタスクを完了にします。"
    } do
      post "/api/subtasks/#{subtask.id}/completion"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["completed"]).to be true
    end

    it "存在しないサブタスクなら404を返す", openapi: {
      summary: "サブタスクを完了にする",
      description: "指定したIDのサブタスクがない場合は404を返します。"
    } do
      post "/api/subtasks/999999/completion"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/subtasks/:subtask_id/completion" do
    it "サブタスクを未完了に戻す", openapi: {
      summary: "サブタスクの完了を取り消す",
      description: "完了済みのサブタスクを未完了に戻します。"
    } do
      subtask.complete!

      delete "/api/subtasks/#{subtask.id}/completion"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["completed"]).to be false
    end
  end

  describe "POST /api/todos/:todo_id/completion" do
    # 親の完了をサブタスクの状態で止めない（業務ルールにしない）。仕様書には記録しない。
    it "未完了のサブタスクがあっても親ToDoを完了にできる", openapi: false do
      post "/api/todos/#{todo.id}/completion"

      expect(response).to have_http_status(:ok)
      expect(todo.reload).to be_completed
    end
  end

  describe "DELETE /api/todos/:id" do
    it "ToDoを消すとサブタスクも消える", openapi: false do
      delete "/api/todos/#{todo.id}"

      expect(response).to have_http_status(:no_content)
      expect(Subtask.count).to eq(0)
    end
  end
end
