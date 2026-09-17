class ListDetailResource < ListResource
  many :todos, resource: TodoResource
end
