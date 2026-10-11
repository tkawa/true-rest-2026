# 実験の初期状態。再生成しても同じ内容になるよう、IDと時刻を明示する。
BASE_TIME = Time.utc(2026, 1, 1, 0, 0, 0)

Comment.delete_all
Subtask.delete_all
Todo.delete_all
List.delete_all

lists = [
  { id: 1, name: "仕事", archived_at: nil },
  { id: 2, name: "買い物リスト", archived_at: nil },
  { id: 3, name: "2025年の目標", archived_at: BASE_TIME }
]

todos = [
  { id: 1, list_id: 1, title: "週次ミーティングの準備", completed_at: nil },
  { id: 2, list_id: 1, title: "経費精算", completed_at: nil },
  { id: 3, list_id: 1, title: "月次レポート提出", completed_at: BASE_TIME },
  { id: 4, list_id: 2, title: "卵", completed_at: nil },
  { id: 5, list_id: 2, title: "パン", completed_at: BASE_TIME },
  { id: 6, list_id: 3, title: "本を12冊読む", completed_at: BASE_TIME },
  { id: 7, list_id: 3, title: "フルマラソン完走", completed_at: nil }
]

# SEED_VARIANT=due: 期限（due_on）つきの 9 行。「今日」は 2026-03-04 を想定している。
if ENV["SEED_VARIANT"] == "due"
  due = {
    1 => Date.new(2026, 3, 2), 2 => Date.new(2026, 3, 3), 3 => Date.new(2026, 2, 27),
    4 => Date.new(2026, 3, 4), 7 => Date.new(2026, 3, 1)
  }
  todos = todos.map { |attrs| attrs.merge(due_on: due[attrs[:id]]) }
  todos += [
    { id: 8, list_id: 1, title: "来期の計画", completed_at: nil, due_on: Date.new(2026, 3, 4) },
    { id: 9, list_id: 1, title: "勉強会の申込", completed_at: nil, due_on: Date.new(2026, 3, 11) }
  ]
end

List.insert_all!(lists.map { |attrs| attrs.merge(created_at: BASE_TIME, updated_at: BASE_TIME) })
Todo.insert_all!(todos.map { |attrs| attrs.merge(created_at: BASE_TIME, updated_at: BASE_TIME) })

# SEED_VARIANT=comments: ToDo 2（経費精算）に、失われると困る内容のコメントを二件付ける。
if ENV["SEED_VARIANT"] == "comments"
  Comment.insert_all!([
    { id: 1, todo_id: 2, body: "領収書は経理の田中さんに提出済み。交通費の分だけ未提出" },
    { id: 2, todo_id: 2, body: "10/15 までに出さないと今月分に間に合わないとのこと" }
  ].map { |attrs| attrs.merge(created_at: BASE_TIME, updated_at: BASE_TIME) })
end

# SEED_VARIANT=subtasks: ToDo 1（週次ミーティングの準備）に、未完了を一つ含むサブタスクを二つ付ける。
if ENV["SEED_VARIANT"] == "subtasks"
  Subtask.insert_all!([
    { id: 1, todo_id: 1, title: "議題を集める", completed_at: BASE_TIME },
    { id: 2, todo_id: 1, title: "会議室を予約する", completed_at: nil }
  ].map { |attrs| attrs.merge(created_at: BASE_TIME, updated_at: BASE_TIME) })
end
