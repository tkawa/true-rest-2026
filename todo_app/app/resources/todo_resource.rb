class TodoResource
  include Alba::Resource

  attributes :id, :list_id, :title
  attribute(:completed) { |todo| todo.completed? }
  attributes :completed_at, :created_at, :updated_at
end
