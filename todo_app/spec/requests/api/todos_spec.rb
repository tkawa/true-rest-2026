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
    comments_links = Rails.configuration.x.api.links && Rails.configuration.x.features.comments
    subtasks_links = Rails.configuration.x.api.links && Rails.configuration.x.features.subtasks

    it "ToDoを返す", openapi: {
      summary: "ToDo詳細",
      description: [
        "ToDoを1件返します。completed は完了済みかどうかを表します。",
        ("due_on は期限の日付です。" if Rails.configuration.x.features.due),
        ("comments_count はコメント数、links.comments はコメント一覧のURLです。" if comments_links),
        ("subtasks_count はサブタスク数、open_subtasks_count は未完了のサブタスク数、links.subtasks はサブタスク一覧のURLです。" if subtasks_links),
        ("overdue は、未完了で期限が今日より前なら true です。" if Rails.configuration.x.api.situated)
      ].compact.join(" ")
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
      description: OpenapiText.pick(
        full: "ToDoのタイトルだけを変更します。完了状態はこの操作では変わりません。",
        terse: "ToDoのタイトルを変更します。"
      )
    } do
      patch "/api/todos/#{todo.id}", params: { todo: { title: "変更後のテストToDo" } }, as: :json

      if Rails.configuration.x.responses.update_no_content
        expect(response).to have_http_status(:no_content)
        expect(response.body).to be_empty
      else
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["title"]).to eq("変更後のテストToDo")
      end
      expect(todo.reload.title).to eq("変更後のテストToDo")
    end

    it "完了済みなら422を返す", openapi: {
      summary: "ToDoのタイトル変更",
      description: [
        "完了済みのToDoは編集できず、422を返します。先に DELETE /todos/{todo_id}/completion で完了を取り消してください。",
        ("タイトルは100文字以内です。超える場合は422を返します。" if Rails.configuration.x.features.title_limit)
      ].compact.join(" ")
    } do
      todo.complete!

      patch "/api/todos/#{todo.id}", params: { todo: { title: "変更後のテストToDo" } }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to eq([ "完了済みのToDoは編集できません。先に再開してください" ])
    end
  end

  describe "PATCH /api/todos/:id（期限）" do
    it "期限を変える", if: Rails.configuration.x.features.due, openapi: {
      summary: "ToDoのタイトル変更",
      description: [
        OpenapiText.pick(
          full: "ToDoのタイトルだけを変更します。完了状態はこの操作では変わりません。",
          terse: "ToDoのタイトルを変更します。"
        ),
        "due_on は期限の日付（YYYY-MM-DD）です。未設定にするには null を送ります。"
      ].join(" ")
    } do
      patch "/api/todos/#{todo.id}", params: { todo: { title: "変更後のテストToDo", due_on: "2026-03-06" } }, as: :json

      if Rails.configuration.x.responses.update_no_content
        expect(response).to have_http_status(:no_content)
      else
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["due_on"]).to eq("2026-03-06")
      end
      expect(todo.reload.due_on).to eq(Date.new(2026, 3, 6))
    end

    it "null を送ると期限を外す", if: Rails.configuration.x.features.due, openapi: false do
      todo.update!(due_on: Date.new(2026, 3, 6))

      patch "/api/todos/#{todo.id}", params: { todo: { due_on: nil } }, as: :json

      expect(todo.reload.due_on).to be_nil
    end

    it "完了済みでも期限は変えられる", if: Rails.configuration.x.features.due, openapi: false do
      todo.complete!

      patch "/api/todos/#{todo.id}", params: { todo: { due_on: "2026-03-06" } }, as: :json

      expect(todo.reload.due_on).to eq(Date.new(2026, 3, 6))
    end
  end

  describe "PATCH /api/todos/:id（タイトルの文字数上限）" do
    # 挙動の検証だけを行い、仕様書には記録しない（同じ 422 の説明を後勝ちで上書きするため）。
    # 100文字の一文は、完了済みの 422 の description に載せている。
    it "タイトルが100文字を超えると422を返す", if: Rails.configuration.x.features.title_limit, openapi: false do
      patch "/api/todos/#{todo.id}", params: { todo: { title: "あ" * 101 } }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to be_present
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
