class SubtaskResource
  include Alba::Resource

  attributes :id, :todo_id, :title
  attribute(:completed) { |subtask| subtask.completed? }
  attributes :completed_at, :created_at, :updated_at
end
