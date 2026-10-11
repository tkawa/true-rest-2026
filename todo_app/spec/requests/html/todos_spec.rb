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

  describe "期限（FEATURE_DUE）", if: Rails.configuration.x.features.due do
    it "リスト詳細に今日と期限、期限切れの印を出す" do
      overdue = list.todos.create!(title: "遅れたToDo", due_on: Rails.configuration.x.today - 1)
      list.todos.create!(title: "今日のToDo", due_on: Rails.configuration.x.today)

      get list_path(list)

      expect(response.body).to include("今日: #{Rails.configuration.x.today.iso8601}（")
      expect(response.body.scan("期限切れ").size).to eq(1)
      expect(response.body).to include("期限: #{overdue.due_on.iso8601}")
    end

    it "編集フォームに期限の date 入力を出す" do
      get edit_todo_path(todo)

      expect(response.body).to include(%(type="date"))
      expect(response.body).to include(%(name="todo[due_on]"))
    end
  end

  describe "コメント（FEATURE_COMMENTS）", if: Rails.configuration.x.features.comments do
    it "行にコメント件数を、詳細にコメントの本文を出す" do
      todo.comments.create!(body: "一つ目のコメント")
      todo.comments.create!(body: "二つ目のコメント")

      get list_path(list)
      expect(response.body).to include("コメント 2件")

      get todo_path(todo)
      expect(response.body).to include("一つ目のコメント", "二つ目のコメント")
    end

    it "コメントがないToDoの行には件数を出さない" do
      get list_path(list)

      expect(response.body).not_to include("コメント ")
    end

    it "コメントを追加する" do
      post todo_comments_path(todo), params: { comment: { body: "追加したコメント" } }

      expect(response).to redirect_to(todo_path(todo))
      expect(todo.comments.pluck(:body)).to eq([ "追加したコメント" ])
    end
  end

  describe "サブタスク（FEATURE_SUBTASKS）", if: Rails.configuration.x.features.subtasks do
    it "行の下にサブタスクと完了数を出し、完了済みは取り消し線にする" do
      todo.subtasks.create!(title: "終わったサブタスク", completed_at: Time.current)
      todo.subtasks.create!(title: "残っているサブタスク")

      get list_path(list)

      expect(response.body).to include("サブタスク 1/2 完了")
      expect(response.body).to include("<s>終わったサブタスク</s>")
      expect(response.body).to include("残っているサブタスク")
    end

    it "サブタスクを完了にする" do
      subtask = todo.subtasks.create!(title: "残っているサブタスク")

      post subtask_completion_path(subtask)

      expect(response).to redirect_to(list_path(list))
      expect(subtask.reload).to be_completed
    end
  end
end
