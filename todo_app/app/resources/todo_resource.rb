class TodoResource
  include Alba::Resource

  attributes :id, :list_id, :title
  attribute(:completed) { |todo| todo.completed? }
  attributes :completed_at
  attributes :due_on if Rails.configuration.x.features.due
  attribute(:overdue) { |todo| todo.overdue?(Rails.configuration.x.today) } if Rails.configuration.x.api.situated
  attributes :created_at, :updated_at
  if Rails.configuration.x.api.links
    comments = Rails.configuration.x.features.comments
    subtasks = Rails.configuration.x.features.subtasks
    attribute(:comments_count) { |todo| todo.comments.count } if comments
    if subtasks
      attribute(:subtasks_count) { |todo| todo.subtasks.count }
      attribute(:open_subtasks_count) { |todo| todo.subtasks.where(completed_at: nil).count }
    end
    if comments || subtasks
      attribute(:links) do |todo|
        {}.tap do |links|
          links[:comments] = "/api/todos/#{todo.id}/comments" if comments
          links[:subtasks] = "/api/todos/#{todo.id}/subtasks" if subtasks
        end
      end
    end
  end
end
