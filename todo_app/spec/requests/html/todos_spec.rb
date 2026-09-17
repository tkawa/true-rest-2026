require "rails_helper"

RSpec.describe "HTML表現のToDo", type: :request do
  let!(:list) { List.create!(name: "テスト用リスト") }
  let!(:todo) { list.todos.create!(title: "テストToDo") }

  describe "GET /todos/:id/edit" do
    it "未完了なら編集フォームを出す" do
      get edit_todo_path(todo)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(action="/todos/#{todo.id}"))
    end

    it "完了済みならToDo詳細へリダイレクトする" do
      todo.complete!

      get edit_todo_path(todo)

      expect(response).to redirect_to(todo_path(todo))
      expect(flash[:alert]).to eq("完了済みのToDoは編集できません")
    end
  end

  describe "PATCH /todos/:id" do
    it "タイトルを変えてリスト詳細へ戻る" do
      patch todo_path(todo), params: { todo: { title: "変更後のテストToDo" } }

      expect(response).to redirect_to(list_path(list))
      expect(todo.reload.title).to eq("変更後のテストToDo")
    end

    it "完了済みなら422でフォームを再描画する" do
      todo.complete!

      patch todo_path(todo), params: { todo: { title: "変更後のテストToDo" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("完了済みのToDoは編集できません。先に再開してください")
    end
  end

  describe "完了と再開" do
    it "POST /todos/:todo_id/completion で完了する" do
      post todo_completion_path(todo)

      expect(response).to redirect_to(list_path(list))
      expect(todo.reload).to be_completed
    end

    it "DELETE /todos/:todo_id/completion で再開する" do
      todo.complete!

      delete todo_completion_path(todo)

      expect(response).to redirect_to(list_path(list))
      expect(todo.reload).not_to be_completed
    end
  end

  describe "DELETE /todos/:id" do
    it "削除してリスト詳細へ戻る" do
      delete todo_path(todo)

      expect(response).to redirect_to(list_path(list))
      expect(Todo.exists?(todo.id)).to be false
    end
  end
end
