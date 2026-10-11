class CreateSubtasks < ActiveRecord::Migration[8.1]
  def change
    create_table :subtasks do |t|
      t.references :todo, null: false, foreign_key: true
      t.string :title, null: false
      t.datetime :completed_at

      t.timestamps
    end
  end
end
