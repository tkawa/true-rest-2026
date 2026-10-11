class CreateComments < ActiveRecord::Migration[8.1]
  def change
    create_table :comments do |t|
      t.references :todo, null: false, foreign_key: true
      t.text :body, null: false

      t.timestamps
    end
  end
end
