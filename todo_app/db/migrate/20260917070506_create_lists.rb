class CreateLists < ActiveRecord::Migration[8.1]
  def change
    create_table :lists do |t|
      t.string :name, null: false
      t.datetime :archived_at

      t.timestamps
    end
  end
end
