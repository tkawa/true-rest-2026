class ListResource
  include Alba::Resource

  attributes :id, :name
  attribute(:archived) { |list| list.archived? }
  attributes :archived_at, :created_at, :updated_at
end
