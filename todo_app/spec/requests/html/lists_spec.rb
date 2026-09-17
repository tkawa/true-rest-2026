require "rails_helper"

RSpec.describe "HTML表現のリスト", type: :request do
  let!(:list) { List.create!(name: "テスト用リスト") }

  describe "GET /" do
    it "現行のリストをリンクで並べる" do
      get root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(href="/lists/#{list.id}"))
      expect(response.body).to include("新しいリスト")
    end

    it "アーカイブ済みがなければ見出しを出さない" do
      get root_path

      expect(response.body).not_to include("アーカイブ済み")
    end

    it "アーカイブ済みがあれば見出しの下に並べる" do
      List.create!(name: "テスト用アーカイブリスト").archive!

      get root_path

      expect(response.body).to include("アーカイブ済み")
      expect(response.body).to include("テスト用アーカイブリスト")
    end
  end

  describe "GET /lists/:id" do
    it "未完了の行に完了ボタンと編集リンクを出す" do
      todo = list.todos.create!(title: "テストToDo")

      get list_path(list)

      expect(response.body).to include(%(href="/todos/#{todo.id}/edit"))
      expect(response.body).to include("完了")
    end

    it "完了済みの行に編集リンクを出さない" do
      todo = list.todos.create!(title: "テストToDo")
      todo.complete!

      get list_path(list)

      expect(response.body).not_to include(%(href="/todos/#{todo.id}/edit"))
      expect(response.body).to include("再開")
    end

    it "追加フォームを出す" do
      get list_path(list)

      expect(response.body).to include(%(action="/lists/#{list.id}/todos"))
      expect(response.body).to include(%(name="todo[title]"))
    end

    it "アーカイブ済みなら追加フォームの代わりに説明文を出す" do
      list.archive!

      get list_path(list)

      expect(response.body).not_to include(%(action="/lists/#{list.id}/todos"))
      expect(response.body).to include("このリストはアーカイブ済みです。ToDoは追加できません。")
    end
  end

  describe "HTML表現に /api が漏れないこと" do
    it "リスト詳細のどこにも /api が現れない" do
      list.todos.create!(title: "テストToDo")

      get list_path(list)

      expect(response.body).not_to include("/api")
    end
  end

  describe "POST /lists/:list_id/todos" do
    it "追加してリスト詳細へ戻る" do
      post list_todos_path(list), params: { todo: { title: "テストToDo" } }

      expect(response).to redirect_to(list_path(list))
      expect(list.todos.pluck(:title)).to include("テストToDo")
    end

    it "アーカイブ済みなら戻ってalertを出し、追加されない" do
      list.archive!

      post list_todos_path(list), params: { todo: { title: "テストToDo" } }

      expect(response).to redirect_to(list_path(list))
      expect(flash[:alert]).to include("アーカイブ済みのリストにはToDoを追加できません")
      expect(list.todos).to be_empty
    end
  end

  describe "GET /lists/:id で存在しないID" do
    it "本番相当の404ページを返す" do
      get list_path(id: 999_999)

      expect(response).to have_http_status(:not_found)
    end
  end
end
