class CommentResource
  include Alba::Resource

  attributes :id, :todo_id, :body, :created_at, :updated_at
end
