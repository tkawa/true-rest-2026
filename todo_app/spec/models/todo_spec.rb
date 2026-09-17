require "rails_helper"

RSpec.describe Todo do
  let(:list) { List.create!(name: "テスト用リスト") }

  describe "バリデーション" do
    it "タイトルが空なら無効" do
      todo = list.todos.build(title: "")

      expect(todo).not_to be_valid
      expect(todo.errors[:title]).to be_present
    end
  end

  describe "業務ルール: アーカイブ済みのリストには追加できない" do
    it "アーカイブ済みのリストへの新規作成を拒む" do
      list.archive!
      todo = list.todos.build(title: "テストToDo")

      expect(todo).not_to be_valid
      expect(todo.errors[:base]).to include("アーカイブ済みのリストにはToDoを追加できません")
    end

    it "作成済みのToDoは、リストがアーカイブされても更新できる" do
      todo = list.todos.create!(title: "テストToDo")
      list.archive!

      expect(todo.update(title: "変更後のテストToDo")).to be true
    end
  end

  describe "業務ルール: 完了済みのタイトルは変更できない" do
    let(:todo) { list.todos.create!(title: "テストToDo") }

    it "完了済みのタイトル変更を拒む" do
      todo.complete!

      expect(todo.update(title: "変更後のテストToDo")).to be false
      expect(todo.errors[:base]).to include("完了済みのToDoは編集できません。先に再開してください")
    end

    it "未完了ならタイトルを変更できる" do
      expect(todo.update(title: "変更後のテストToDo")).to be true
    end

    it "完了済みでもタイトル以外の変更は通る" do
      todo.complete!

      expect(todo.reopen!).to be true
    end
  end

  describe "#complete! / #reopen!" do
    let(:todo) { list.todos.create!(title: "テストToDo") }

    it "完了すると completed_at が入る" do
      expect { todo.complete! }.to change { todo.reload.completed? }.from(false).to(true)
    end

    it "再開すると completed_at が消える" do
      todo.complete!

      expect { todo.reopen! }.to change { todo.reload.completed? }.from(true).to(false)
    end
  end
end
