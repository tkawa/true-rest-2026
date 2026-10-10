class ListResource
  include Alba::Resource

  attributes :id, :name
  attribute(:archived) { |list| list.archived? }
  attributes :archived_at
  attribute(:today) { |_list| Rails.configuration.x.today.iso8601 } if Rails.configuration.x.api.situated
  attributes :created_at, :updated_at
end
