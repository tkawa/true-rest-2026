class CreateTodos < ActiveRecord::Migration[8.1]
  def change
    create_table :todos do |t|
      t.references :list, null: false, foreign_key: true
      t.string :title, null: false
      t.datetime :completed_at

      t.timestamps
    end
  end
end
