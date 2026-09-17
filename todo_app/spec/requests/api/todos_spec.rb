require "rails_helper"

RSpec.describe "Todos", type: :request do
  let!(:list) { List.create!(name: "テスト用リスト") }
  let!(:todo) { list.todos.create!(title: "テストToDo") }

  describe "POST /api/lists/:list_id/todos" do
    it "ToDoを追加する", openapi: {
      summary: "ToDo追加",
      description: "指定したリストにToDoを追加します。作成後のURLは Location ヘッダに入ります。"
    } do
      post "/api/lists/#{list.id}/todos", params: { todo: { title: "追加したテストToDo" } }, as: :json

      expect(response).to have_http_status(:created)
      expect(response.headers["Location"]).to eq("http://www.example.com/api/todos/#{Todo.last.id}")
      expect(response.parsed_body["completed"]).to be false
    end

    it "アーカイブ済みのリストには追加できず422を返す", openapi: {
      summary: "ToDo追加",
      description: "アーカイブ済みのリストにはToDoを追加できず、422を返します。先にアーカイブを解除してください。"
    } do
      list.archive!

      post "/api/lists/#{list.id}/todos", params: { todo: { title: "追加したテストToDo" } }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to eq([ "アーカイブ済みのリストにはToDoを追加できません" ])
    end

    it "存在しないリストなら404を返す", openapi: {
      summary: "ToDo追加",
      description: "指定したIDのリストがない場合は404を返します。"
    } do
      post "/api/lists/999999/todos", params: { todo: { title: "追加したテストToDo" } }, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/todos/:id" do
    it "ToDoを返す", openapi: {
      summary: "ToDo詳細",
      description: "ToDoを1件返します。completed は完了済みかどうかを表します。"
    } do
      get "/api/todos/#{todo.id}"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["title"]).to eq("テストToDo")
    end

    it "存在しないIDなら404を返す", openapi: {
      summary: "ToDo詳細",
      description: "指定したIDのToDoがない場合は404を返します。"
    } do
      get "/api/todos/999999"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /api/todos/:id" do
    it "タイトルを変える", openapi: {
      summary: "ToDoのタイトル変更",
      description: "ToDoのタイトルだけを変更します。完了状態はこの操作では変わりません。"
    } do
      patch "/api/todos/#{todo.id}", params: { todo: { title: "変更後のテストToDo" } }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["title"]).to eq("変更後のテストToDo")
    end

    it "完了済みなら422を返す", openapi: {
      summary: "ToDoのタイトル変更",
      description: "完了済みのToDoは編集できず、422を返します。先に DELETE /todos/{todo_id}/completion で完了を取り消してください。"
    } do
      todo.complete!

      patch "/api/todos/#{todo.id}", params: { todo: { title: "変更後のテストToDo" } }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to eq([ "完了済みのToDoは編集できません。先に再開してください" ])
    end
  end

  describe "DELETE /api/todos/:id" do
    it "ToDoを消す", openapi: {
      summary: "ToDo削除",
      description: "ToDoを1件削除します。"
    } do
      delete "/api/todos/#{todo.id}"

      expect(response).to have_http_status(:no_content)
      expect(Todo.exists?(todo.id)).to be false
    end
  end
end
