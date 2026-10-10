class TodoResource
  include Alba::Resource

  attributes :id, :list_id, :title
  attribute(:completed) { |todo| todo.completed? }
  attributes :completed_at
  attributes :due_on if Rails.configuration.x.features.due
  attribute(:overdue) { |todo| todo.overdue?(Rails.configuration.x.today) } if Rails.configuration.x.api.situated
  attributes :created_at, :updated_at
end
