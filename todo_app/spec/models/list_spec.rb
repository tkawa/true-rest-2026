require "rails_helper"

RSpec.describe List do
  describe "バリデーション" do
    it "名前が空なら無効" do
      list = List.new(name: "")

      expect(list).not_to be_valid
      expect(list.errors[:name]).to be_present
    end
  end

  describe "#archived?" do
    it "archived_at が入っていれば true" do
      expect(List.new(archived_at: Time.current)).to be_archived
      expect(List.new(archived_at: nil)).not_to be_archived
    end
  end

  describe "#archive! / #unarchive!" do
    let(:list) { List.create!(name: "テスト用リスト") }

    it "アーカイブすると archived_at が入る" do
      expect { list.archive! }.to change { list.reload.archived? }.from(false).to(true)
    end

    it "アーカイブを解除すると archived_at が消える" do
      list.archive!

      expect { list.unarchive! }.to change { list.reload.archived? }.from(true).to(false)
    end
  end

  describe "#todos" do
    it "リストを消すと所属するToDoも消える" do
      list = List.create!(name: "テスト用リスト")
      list.todos.create!(title: "テストToDo")

      expect { list.destroy! }.to change(Todo, :count).by(-1)
    end
  end
end
