「仕事」リストで期限切れになっているToDoの期限を、すべて明日に延ばして

操作対象のサービスの仕様書（OpenAPI）:
```yaml
---
openapi: 3.2.0
info:
  title: ToDo API
  version: 1.0.0
servers:
- url: http://localhost:3013/api
paths:
  "/lists":
    get:
      summary: リスト一覧
      tags:
      - List
      responses:
        '200':
          description: アーカイブ済みを含むすべてのリストを返します。archived が true のリストにはToDoを追加できません。
            today はサーバの今日の日付（YYYY-MM-DD）で、期限の計算の基準です。
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
                    today:
                      type: string
                    created_at:
                      type: string
                    updated_at:
                      type: string
                  required:
                  - id
                  - name
                  - archived
                  - archived_at
                  - today
                  - created_at
                  - updated_at
              example:
              - id: 1
                name: テスト用リスト
                archived: false
                archived_at:
                today: '2026-03-04'
                created_at: '2026-01-01T00:00:00.000Z'
                updated_at: '2026-01-01T00:00:00.000Z'
              - id: 2
                name: テスト用アーカイブリスト
                archived: true
                archived_at: '2026-01-01T00:00:00.000Z'
                today: '2026-03-04'
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
                  today:
                    type: string
                  created_at:
                    type: string
                  updated_at:
                    type: string
                required:
                - id
                - name
                - archived
                - archived_at
                - today
                - created_at
                - updated_at
              example:
                id: 2
                name: 新しいテスト用リスト
                archived: false
                archived_at:
                today: '2026-03-04'
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
          description: リストと、そのリストに属するToDoをまとめて返します。 today はサーバの今日の日付（YYYY-MM-DD）で、期限の計算の基準です。
            overdue は、未完了で期限が今日より前なら true です。
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
                  today:
                    type: string
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
                        due_on:
                          type: 'null'
                        overdue:
                          type: boolean
                        created_at:
                          type: string
                        updated_at:
                          type: string
                      required:
                      - id
                      - list_id
                      - title
                      - completed
                      - completed_at
                      - due_on
                      - overdue
                      - created_at
                      - updated_at
                required:
                - id
                - name
                - archived
                - archived_at
                - today
                - created_at
                - updated_at
                - todos
              example:
                id: 1
                name: テスト用リスト
                archived: false
                archived_at:
                today: '2026-03-04'
                created_at: '2026-01-01T00:00:00.000Z'
                updated_at: '2026-01-01T00:00:00.000Z'
                todos:
                - id: 1
                  list_id: 1
                  title: テストToDo
                  completed: false
                  completed_at:
                  due_on:
                  overdue: false
                  created_at: '2026-01-01T00:00:00.000Z'
                  updated_at: '2026-01-01T00:00:00.000Z'
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
                  today:
                    type: string
                  created_at:
                    type: string
                  updated_at:
                    type: string
                required:
                - id
                - name
                - archived
                - archived_at
                - today
                - created_at
                - updated_at
              example:
                id: 1
                name: 変更後のテスト用リスト
                archived: false
                archived_at:
                today: '2026-03-04'
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
                  due_on:
                    type: 'null'
                  overdue:
                    type: boolean
                  created_at:
                    type: string
                  updated_at:
                    type: string
                required:
                - id
                - list_id
                - title
                - completed
                - completed_at
                - due_on
                - overdue
                - created_at
                - updated_at
              example:
                id: 2
                list_id: 1
                title: 追加したテストToDo
                completed: false
                completed_at:
                due_on:
                overdue: false
                created_at: '2026-01-01T00:00:00.000Z'
                updated_at: '2026-01-01T00:00:00.000Z'
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
          description: ToDoを1件返します。completed は完了済みかどうかを表します。 due_on は期限の日付です。 overdue
            は、未完了で期限が今日より前なら true です。
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
                  due_on:
                    type: 'null'
                  overdue:
                    type: boolean
                  created_at:
                    type: string
                  updated_at:
                    type: string
                required:
                - id
                - list_id
                - title
                - completed
                - completed_at
                - due_on
                - overdue
                - created_at
                - updated_at
              example:
                id: 1
                list_id: 1
                title: テストToDo
                completed: false
                completed_at:
                due_on:
                overdue: false
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
                    due_on:
                      type: string
                  required:
                  - title
              required:
              - todo
            example:
              todo:
                title: 変更後のテストToDo
                due_on: '2026-03-06'
      responses:
        '200':
          description: ToDoのタイトルだけを変更します。完了状態はこの操作では変わりません。 due_on は期限の日付（YYYY-MM-DD）です。未設定にするには
            null を送ります。
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
                  due_on:
                    type:
                    - string
                    - 'null'
                  overdue:
                    type: boolean
                  created_at:
                    type: string
                  updated_at:
                    type: string
                required:
                - id
                - list_id
                - title
                - completed
                - completed_at
                - due_on
                - overdue
                - created_at
                - updated_at
              example:
                id: 1
                list_id: 1
                title: 変更後のテストToDo
                completed: false
                completed_at:
                due_on: '2026-03-06'
                overdue: false
                created_at: '2026-01-01T00:00:00.000Z'
                updated_at: '2026-01-01T00:00:00.000Z'
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
                  due_on:
                    type: 'null'
                  overdue:
                    type: boolean
                  created_at:
                    type: string
                  updated_at:
                    type: string
                required:
                - id
                - list_id
                - title
                - completed
                - completed_at
                - due_on
                - overdue
                - created_at
                - updated_at
              example:
                id: 1
                list_id: 1
                title: テストToDo
                completed: false
                completed_at:
                due_on:
                overdue: false
                created_at: '2026-01-01T00:00:00.000Z'
                updated_at: '2026-01-01T00:00:00.000Z'
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
                  due_on:
                    type: 'null'
                  overdue:
                    type: boolean
                  created_at:
                    type: string
                  updated_at:
                    type: string
                required:
                - id
                - list_id
                - title
                - completed
                - completed_at
                - due_on
                - overdue
                - created_at
                - updated_at
              example:
                id: 1
                list_id: 1
                title: テストToDo
                completed: true
                completed_at: '2026-01-01T00:00:00.000Z'
                due_on:
                overdue: false
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

```
