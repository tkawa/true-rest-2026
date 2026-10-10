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

  describe "タイトルの文字数上限（FEATURE_TITLE_LIMIT）" do
    around do |example|
      original = Rails.configuration.x.features.title_limit
      Rails.configuration.x.features.title_limit = flag
      example.run
    ensure
      Rails.configuration.x.features.title_limit = original
    end

    context "フラグ ON" do
      let(:flag) { true }

      it "101文字は無効" do
        todo = list.todos.build(title: "あ" * 101)

        expect(todo).not_to be_valid
        expect(todo.errors.full_messages).to include("タイトルは100文字以内で入力してください")
      end

      it "100文字は有効" do
        expect(list.todos.build(title: "あ" * 100)).to be_valid
      end
    end

    context "フラグ OFF" do
      let(:flag) { false }

      it "101文字も有効" do
        expect(list.todos.build(title: "あ" * 101)).to be_valid
      end
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

  describe "#overdue?" do
    let(:today) { Date.new(2026, 3, 4) }

    it "未完了で期限が今日より前なら期限切れ" do
      expect(list.todos.build(title: "x", due_on: today - 1)).to be_overdue(today)
    end

    it "今日が期限なら期限切れではない" do
      expect(list.todos.build(title: "x", due_on: today)).not_to be_overdue(today)
    end

    it "完了済みなら期限が過去でも期限切れではない" do
      expect(list.todos.build(title: "x", due_on: today - 1, completed_at: Time.current)).not_to be_overdue(today)
    end

    it "期限がなければ期限切れではない" do
      expect(list.todos.build(title: "x")).not_to be_overdue(today)
    end
  end
end
