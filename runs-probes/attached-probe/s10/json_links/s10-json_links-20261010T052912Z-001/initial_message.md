「仕事」リストの「週次ミーティングの準備」を完了にして。ただし、やり残しがあるなら完了にしないで、何が残っているか教えて

操作対象のサービスの仕様書（OpenAPI）:
```yaml
---
openapi: 3.2.0
info:
  title: ToDo API
  version: 1.0.0
servers:
- url: http://localhost:3015/api
paths:
  "/lists":
    get:
      summary: リスト一覧
      tags:
      - List
      responses:
        '200':
          description: アーカイブ済みを含むすべてのリストを返します。archived が true のリストにはToDoを追加できません。
          content:
            application/json:
              schema:
                type: array
                items:
                  type: object
                  properties:
                    id:
                      type: integer
                    name:
                      type: string
                    archived:
                      type: boolean
                    archived_at:
                      type:
                      - string
                      - 'null'
                    created_at:
                      type: string
                    updated_at:
                      type: string
                  required:
                  - id
                  - name
                  - archived
                  - archived_at
                  - created_at
                  - updated_at
              example:
              - id: 1
                name: テスト用リスト
                archived: false
                archived_at:
                created_at: '2026-01-01T00:00:00.000Z'
                updated_at: '2026-01-01T00:00:00.000Z'
              - id: 2
                name: テスト用アーカイブリスト
                archived: true
                archived_at: '2026-01-01T00:00:00.000Z'
                created_at: '2026-01-01T00:00:00.000Z'
                updated_at: '2026-01-01T00:00:00.000Z'
    post:
      summary: リスト作成
      tags:
      - List
      requestBody:
        content:
          application/json:
            schema:
              type: object
              properties:
                list:
                  type: object
                  properties:
                    name:
                      type: string
                  required:
                  - name
              required:
              - list
            example:
              list:
                name: 新しいテスト用リスト
      responses:
        '201':
          description: 名前を指定して新しいリストを作ります。作成後のURLは Location ヘッダに入ります。
          content:
            application/json:
              schema:
                type: object
                properties:
                  id:
                    type: integer
                  name:
                    type: string
                  archived:
                    type: boolean
                  archived_at:
                    type: 'null'
                  created_at:
                    type: string
                  updated_at:
                    type: string
                required:
                - id
                - name
                - archived
                - archived_at
                - created_at
                - updated_at
              example:
                id: 2
                name: 新しいテスト用リスト
                archived: false
                archived_at:
                created_at: '2026-01-01T00:00:00.000Z'
                updated_at: '2026-01-01T00:00:00.000Z'
        '422':
          description: 名前は必須です。空の場合は422を返します。
          content:
            application/json:
              schema:
                type: object
                properties:
                  errors:
                    type: array
                    items:
                      type: string
                required:
                - errors
              example:
                errors:
                - 名前を入力してください
  "/lists/{id}":
    delete:
      summary: リスト削除
      tags:
      - List
      parameters:
      - name: id
        in: path
        required: true
        schema:
          type: integer
        example: 1
      responses:
        '204':
          description: リストと、そのリストに属するToDoをまとめて削除します。
    get:
      summary: リスト詳細
      tags:
      - List
      parameters:
      - name: id
        in: path
        required: true
        schema:
          type: integer
        example: 999999
      responses:
        '200':
          description: リストと、そのリストに属するToDoをまとめて返します。
          content:
            application/json:
              schema:
                type: object
                properties:
                  id:
                    type: integer
                  name:
                    type: string
                  archived:
                    type: boolean
                  archived_at:
                    type: 'null'
                  created_at:
                    type: string
                  updated_at:
                    type: string
                  todos:
                    type: array
                    items:
                      type: object
                      properties:
                        id:
                          type: integer
                        list_id:
                          type: integer
                        title:
                          type: string
                        completed:
                          type: boolean
                        completed_at:
                          type: 'null'
                        created_at:
                          type: string
                        updated_at:
                          type: string
                        subtasks_count:
                          type: integer
                        open_subtasks_count:
                          type: integer
                        links:
                          type: object
                          properties:
                            subtasks:
                              type: string
                          required:
                          - subtasks
                      required:
                      - id
                      - list_id
                      - title
                      - completed
                      - completed_at
                      - created_at
                      - updated_at
                      - subtasks_count
                      - open_subtasks_count
                      - links
                required:
                - id
                - name
                - archived
                - archived_at
                - created_at
                - updated_at
                - todos
              example:
                id: 1
                name: テスト用リスト
                archived: false
                archived_at:
                created_at: '2026-01-01T00:00:00.000Z'
                updated_at: '2026-01-01T00:00:00.000Z'
                todos:
                - id: 1
                  list_id: 1
                  title: テストToDo
                  completed: false
                  completed_at:
                  created_at: '2026-01-01T00:00:00.000Z'
                  updated_at: '2026-01-01T00:00:00.000Z'
                  subtasks_count: 0
                  open_subtasks_count: 0
                  links:
                    subtasks: "/api/todos/1/subtasks"
        '404':
          description: 指定したIDのリストがない場合は404を返します。
          content:
            application/json:
              schema:
                type: object
                properties:
                  errors:
                    type: array
                    items:
                      type: string
                required:
                - errors
              example:
                errors:
                - 見つかりません
    patch:
      summary: リスト名の変更
      tags:
      - List
      parameters:
      - name: id
        in: path
        required: true
        schema:
          type: integer
        example: 1
      requestBody:
        content:
          application/json:
            schema:
              type: object
              properties:
                list:
                  type: object
                  properties:
                    name:
                      type: string
                  required:
                  - name
              required:
              - list
            example:
              list:
                name: 変更後のテスト用リスト
      responses:
        '200':
          description: リストの名前だけを変更します。アーカイブ状態はこの操作では変わりません。
          content:
            application/json:
              schema:
                type: object
                properties:
                  id:
                    type: integer
                  name:
                    type: string
                  archived:
                    type: boolean
                  archived_at:
                    type: 'null'
                  created_at:
                    type: string
                  updated_at:
                    type: string
                required:
                - id
                - name
                - archived
                - archived_at
                - created_at
                - updated_at
              example:
                id: 1
                name: 変更後のテスト用リスト
                archived: false
                archived_at:
                created_at: '2026-01-01T00:00:00.000Z'
                updated_at: '2026-01-01T00:00:00.000Z'
        '422':
          description: 名前は必須です。空の場合は422を返します。
          content:
            application/json:
              schema:
                type: object
                properties:
                  errors:
                    type: array
                    items:
                      type: string
                required:
                - errors
              example:
                errors:
                - 名前を入力してください
  "/lists/{list_id}/todos":
    post:
      summary: ToDo追加
      tags:
      - Todo
      parameters:
      - name: list_id
        in: path
        required: true
        schema:
          type: integer
        example: 999999
      requestBody:
        content:
          application/json:
            schema:
              type: object
              properties:
                todo:
                  type: object
                  properties:
                    title:
                      type: string
                  required:
                  - title
              required:
              - todo
            example:
              todo:
                title: 追加したテストToDo
      responses:
        '201':
          description: 指定したリストにToDoを追加します。作成後のURLは Location ヘッダに入ります。
          content:
            application/json:
              schema:
                type: object
                properties:
                  id:
                    type: integer
                  list_id:
                    type: integer
                  title:
                    type: string
                  completed:
                    type: boolean
                  completed_at:
                    type: 'null'
                  created_at:
                    type: string
                  updated_at:
                    type: string
                  subtasks_count:
                    type: integer
                  open_subtasks_count:
                    type: integer
                  links:
                    type: object
                    properties:
                      subtasks:
                        type: string
                    required:
                    - subtasks
                required:
                - id
                - list_id
                - title
                - completed
                - completed_at
                - created_at
                - updated_at
                - subtasks_count
                - open_subtasks_count
                - links
              example:
                id: 2
                list_id: 1
                title: 追加したテストToDo
                completed: false
                completed_at:
                created_at: '2026-01-01T00:00:00.000Z'
                updated_at: '2026-01-01T00:00:00.000Z'
                subtasks_count: 0
                open_subtasks_count: 0
                links:
                  subtasks: "/api/todos/2/subtasks"
        '404':
          description: 指定したIDのリストがない場合は404を返します。
          content:
            application/json:
              schema:
                type: object
                properties:
                  errors:
                    type: array
                    items:
                      type: string
                required:
                - errors
              example:
                errors:
                - 見つかりません
        '422':
          description: アーカイブ済みのリストにはToDoを追加できず、422を返します。先にアーカイブを解除してください。
          content:
            application/json:
              schema:
                type: object
                properties:
                  errors:
                    type: array
                    items:
                      type: string
                required:
                - errors
              example:
                errors:
                - アーカイブ済みのリストにはToDoを追加できません
  "/subtasks/{subtask_id}/completion":
    delete:
      summary: サブタスクの完了を取り消す
      tags:
      - Subtasks::Completion
      parameters:
      - name: subtask_id
        in: path
        required: true
        schema:
          type: integer
        example: 1
      responses:
        '200':
          description: 完了済みのサブタスクを未完了に戻します。
          content:
            application/json:
              schema:
                type: object
                properties:
                  id:
                    type: integer
                  todo_id:
                    type: integer
                  title:
                    type: string
                  completed:
                    type: boolean
                  completed_at:
                    type: 'null'
                  created_at:
                    type: string
                  updated_at:
                    type: string
                required:
                - id
                - todo_id
                - title
                - completed
                - completed_at
                - created_at
                - updated_at
              example:
                id: 1
                todo_id: 1
                title: テストサブタスク
                completed: false
                completed_at:
                created_at: '2026-01-01T00:00:00.000Z'
                updated_at: '2026-01-01T00:00:00.000Z'
    post:
      summary: サブタスクを完了にする
      tags:
      - Subtasks::Completion
      parameters:
      - name: subtask_id
        in: path
        required: true
        schema:
          type: integer
        example: 999999
      requestBody:
        content:
          application/x-www-form-urlencoded:
            schema:
              type: object
              properties: {}
            example: {}
      responses:
        '200':
          description: サブタスクを完了にします。
          content:
            application/json:
              schema:
                type: object
                properties:
                  id:
                    type: integer
                  todo_id:
                    type: integer
                  title:
                    type: string
                  completed:
                    type: boolean
                  completed_at:
                    type: string
                  created_at:
                    type: string
                  updated_at:
                    type: string
                required:
                - id
                - todo_id
                - title
                - completed
                - completed_at
                - created_at
                - updated_at
              example:
                id: 1
                todo_id: 1
                title: テストサブタスク
                completed: true
                completed_at: '2026-01-01T00:00:00.000Z'
                created_at: '2026-01-01T00:00:00.000Z'
                updated_at: '2026-01-01T00:00:00.000Z'
        '404':
          description: 指定したIDのサブタスクがない場合は404を返します。
          content:
            application/json:
              schema:
                type: object
                properties:
                  errors:
                    type: array
                    items:
                      type: string
                required:
                - errors
              example:
                errors:
                - 見つかりません
  "/todos/{id}":
    delete:
      summary: ToDo削除
      tags:
      - Todo
      parameters:
      - name: id
        in: path
        required: true
        schema:
          type: integer
        example: 1
      responses:
        '204':
          description: ToDoを1件削除します。
    get:
      summary: ToDo詳細
      tags:
      - Todo
      parameters:
      - name: id
        in: path
        required: true
        schema:
          type: integer
        example: 999999
      responses:
        '200':
          description: ToDoを1件返します。completed は完了済みかどうかを表します。 subtasks_count はサブタスク数、open_subtasks_count
            は未完了のサブタスク数、links.subtasks はサブタスク一覧のURLです。
          content:
            application/json:
              schema:
                type: object
                properties:
                  id:
                    type: integer
                  list_id:
                    type: integer
                  title:
                    type: string
                  completed:
                    type: boolean
                  completed_at:
                    type: 'null'
                  created_at:
                    type: string
                  updated_at:
                    type: string
                  subtasks_count:
                    type: integer
                  open_subtasks_count:
                    type: integer
                  links:
                    type: object
                    properties:
                      subtasks:
                        type: string
                    required:
                    - subtasks
                required:
                - id
                - list_id
                - title
                - completed
                - completed_at
                - created_at
                - updated_at
                - subtasks_count
                - open_subtasks_count
                - links
              example:
                id: 1
                list_id: 1
                title: テストToDo
                completed: false
                completed_at:
                created_at: '2026-01-01T00:00:00.000Z'
                updated_at: '2026-01-01T00:00:00.000Z'
                subtasks_count: 0
                open_subtasks_count: 0
                links:
                  subtasks: "/api/todos/1/subtasks"
        '404':
          description: 指定したIDのToDoがない場合は404を返します。
          content:
            application/json:
              schema:
                type: object
                properties:
                  errors:
                    type: array
                    items:
                      type: string
                required:
                - errors
              example:
                errors:
                - 見つかりません
    patch:
      summary: ToDoのタイトル変更
      tags:
      - Todo
      parameters:
      - name: id
        in: path
        required: true
        schema:
          type: integer
        example: 1
      requestBody:
        content:
          application/json:
            schema:
              type: object
              properties:
                todo:
                  type: object
                  properties:
                    title:
                      type: string
                  required:
                  - title
              required:
              - todo
            example:
              todo:
                title: 変更後のテストToDo
      responses:
        '200':
          description: ToDoのタイトルだけを変更します。完了状態はこの操作では変わりません。
          content:
            application/json:
              schema:
                type: object
                properties:
                  id:
                    type: integer
                  list_id:
                    type: integer
                  title:
                    type: string
                  completed:
                    type: boolean
                  completed_at:
                    type: 'null'
                  created_at:
                    type: string
                  updated_at:
                    type: string
                  subtasks_count:
                    type: integer
                  open_subtasks_count:
                    type: integer
                  links:
                    type: object
                    properties:
                      subtasks:
                        type: string
                    required:
                    - subtasks
                required:
                - id
                - list_id
                - title
                - completed
                - completed_at
                - created_at
                - updated_at
                - subtasks_count
                - open_subtasks_count
                - links
              example:
                id: 1
                list_id: 1
                title: 変更後のテストToDo
                completed: false
                completed_at:
                created_at: '2026-01-01T00:00:00.000Z'
                updated_at: '2026-01-01T00:00:00.000Z'
                subtasks_count: 0
                open_subtasks_count: 0
                links:
                  subtasks: "/api/todos/1/subtasks"
        '422':
          description: 完了済みのToDoは編集できず、422を返します。先に DELETE /todos/{todo_id}/completion
            で完了を取り消してください。
          content:
            application/json:
              schema:
                type: object
                properties:
                  errors:
                    type: array
                    items:
                      type: string
                required:
                - errors
              example:
                errors:
                - 完了済みのToDoは編集できません。先に再開してください
  "/todos/{todo_id}/completion":
    delete:
      summary: ToDoの完了を取り消す
      tags:
      - Todos::Completion
      parameters:
      - name: todo_id
        in: path
        required: true
        schema:
          type: integer
        example: 1
      responses:
        '200':
          description: 完了済みのToDoを未完了に戻します。完了済みのタイトルを変更したいときは、先にこの操作を行ってください。
          content:
            application/json:
              schema:
                type: object
                properties:
                  id:
                    type: integer
                  list_id:
                    type: integer
                  title:
                    type: string
                  completed:
                    type: boolean
                  completed_at:
                    type: 'null'
                  created_at:
                    type: string
                  updated_at:
                    type: string
                  subtasks_count:
                    type: integer
                  open_subtasks_count:
                    type: integer
                  links:
                    type: object
                    properties:
                      subtasks:
                        type: string
                    required:
                    - subtasks
                required:
                - id
                - list_id
                - title
                - completed
                - completed_at
                - created_at
                - updated_at
                - subtasks_count
                - open_subtasks_count
                - links
              example:
                id: 1
                list_id: 1
                title: テストToDo
                completed: false
                completed_at:
                created_at: '2026-01-01T00:00:00.000Z'
                updated_at: '2026-01-01T00:00:00.000Z'
                subtasks_count: 0
                open_subtasks_count: 0
                links:
                  subtasks: "/api/todos/1/subtasks"
    post:
      summary: ToDoを完了にする
      tags:
      - Todos::Completion
      parameters:
      - name: todo_id
        in: path
        required: true
        schema:
          type: integer
        example: 999999
      requestBody:
        content:
          application/x-www-form-urlencoded:
            schema:
              type: object
              properties: {}
            example: {}
      responses:
        '200':
          description: ToDoを完了にします。完了済みのToDoはタイトルを変更できなくなります。
          content:
            application/json:
              schema:
                type: object
                properties:
                  id:
                    type: integer
                  list_id:
                    type: integer
                  title:
                    type: string
                  completed:
                    type: boolean
                  completed_at:
                    type: string
                  created_at:
                    type: string
                  updated_at:
                    type: string
                  subtasks_count:
                    type: integer
                  open_subtasks_count:
                    type: integer
                  links:
                    type: object
                    properties:
                      subtasks:
                        type: string
                    required:
                    - subtasks
                required:
                - id
                - list_id
                - title
                - completed
                - completed_at
                - created_at
                - updated_at
                - subtasks_count
                - open_subtasks_count
                - links
              example:
                id: 1
                list_id: 1
                title: テストToDo
                completed: true
                completed_at: '2026-01-01T00:00:00.000Z'
                created_at: '2026-01-01T00:00:00.000Z'
                updated_at: '2026-01-01T00:00:00.000Z'
                subtasks_count: 0
                open_subtasks_count: 0
                links:
                  subtasks: "/api/todos/1/subtasks"
        '404':
          description: 指定したIDのToDoがない場合は404を返します。
          content:
            application/json:
              schema:
                type: object
                properties:
                  errors:
                    type: array
                    items:
                      type: string
                required:
                - errors
              example:
                errors:
                - 見つかりません
  "/todos/{todo_id}/subtasks":
    get:
      summary: サブタスク一覧
      tags:
      - Subtask
      parameters:
      - name: todo_id
        in: path
        required: true
        schema:
          type: integer
        example: 999999
      responses:
        '200':
          description: ToDoのサブタスクをid順に返します。completed は完了済みかどうかを表します。
          content:
            application/json:
              schema:
                type: array
                items:
                  type: object
                  properties:
                    id:
                      type: integer
                    todo_id:
                      type: integer
                    title:
                      type: string
                    completed:
                      type: boolean
                    completed_at:
                      type: 'null'
                    created_at:
                      type: string
                    updated_at:
                      type: string
                  required:
                  - id
                  - todo_id
                  - title
                  - completed
                  - completed_at
                  - created_at
                  - updated_at
              example:
              - id: 1
                todo_id: 1
                title: テストサブタスク
                completed: false
                completed_at:
                created_at: '2026-01-01T00:00:00.000Z'
                updated_at: '2026-01-01T00:00:00.000Z'
              - id: 2
                todo_id: 1
                title: 二つ目のサブタスク
                completed: false
                completed_at:
                created_at: '2026-01-01T00:00:00.000Z'
                updated_at: '2026-01-01T00:00:00.000Z'
        '404':
          description: 指定したIDのToDoがない場合は404を返します。
          content:
            application/json:
              schema:
                type: object
                properties:
                  errors:
                    type: array
                    items:
                      type: string
                required:
                - errors
              example:
                errors:
                - 見つかりません
    post:
      summary: サブタスク追加
      tags:
      - Subtask
      parameters:
      - name: todo_id
        in: path
        required: true
        schema:
          type: integer
        example: 1
      requestBody:
        content:
          application/json:
            schema:
              type: object
              properties:
                subtask:
                  type: object
                  properties:
                    title:
                      type: string
                  required:
                  - title
              required:
              - subtask
            example:
              subtask:
                title: 追加したサブタスク
      responses:
        '201':
          description: ToDoにサブタスクを追加します。title は必須です。
          content:
            application/json:
              schema:
                type: object
                properties:
                  id:
                    type: integer
                  todo_id:
                    type: integer
                  title:
                    type: string
                  completed:
                    type: boolean
                  completed_at:
                    type: 'null'
                  created_at:
                    type: string
                  updated_at:
                    type: string
                required:
                - id
                - todo_id
                - title
                - completed
                - completed_at
                - created_at
                - updated_at
              example:
                id: 2
                todo_id: 1
                title: 追加したサブタスク
                completed: false
                completed_at:
                created_at: '2026-01-01T00:00:00.000Z'
                updated_at: '2026-01-01T00:00:00.000Z'
        '422':
          description: title は必須です。空の場合は422を返します。
          content:
            application/json:
              schema:
                type: object
                properties:
                  errors:
                    type: array
                    items:
                      type: string
                required:
                - errors
              example:
                errors:
                - Titleを入力してください

```
