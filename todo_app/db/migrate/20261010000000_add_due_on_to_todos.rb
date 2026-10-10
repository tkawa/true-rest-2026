class AddDueOnToTodos < ActiveRecord::Migration[8.1]
  def change
    add_column :todos, :due_on, :date
  end
end
