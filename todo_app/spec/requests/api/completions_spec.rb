require "rails_helper"

RSpec.describe "Completions", type: :request do
  let!(:list) { List.create!(name: "テスト用リスト") }
  let!(:todo) { list.todos.create!(title: "テストToDo") }

  describe "POST /api/todos/:todo_id/completion" do
    it "ToDoを完了にする", openapi: {
      summary: "ToDoを完了にする",
      description: "ToDoを完了にします。完了済みのToDoはタイトルを変更できなくなります。"
    } do
      post "/api/todos/#{todo.id}/completion"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["completed"]).to be true
    end

    it "存在しないToDoなら404を返す", openapi: {
      summary: "ToDoを完了にする",
      description: "指定したIDのToDoがない場合は404を返します。"
    } do
      post "/api/todos/999999/completion"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/todos/:todo_id/completion" do
    it "ToDoを未完了に戻す", openapi: {
      summary: "ToDoの完了を取り消す",
      description: "完了済みのToDoを未完了に戻します。完了済みのタイトルを変更したいときは、先にこの操作を行ってください。"
    } do
      todo.complete!

      delete "/api/todos/#{todo.id}/completion"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["completed"]).to be false
    end
  end
end
