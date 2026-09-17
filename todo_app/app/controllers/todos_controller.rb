class TodosController < ApplicationController
  before_action :set_todo, only: %i[show edit update destroy]

  def create
    @list = List.find(params[:list_id])
    @todo = @list.todos.build(todo_params)

    respond_to do |format|
      if @todo.save
        format.html { redirect_to @list, notice: "ToDoを追加しました" }
        format.json { render json: TodoResource.new(@todo), status: :created, location: api_todo_url(@todo) }
      else
        format.html { redirect_to @list, alert: @todo.errors.full_messages.to_sentence }
        format.json { render json: { errors: @todo.errors.full_messages }, status: :unprocessable_content }
      end
    end
  end

  def show
    respond_to do |format|
      format.html
      format.json { render json: TodoResource.new(@todo) }
    end
  end

  def edit
    redirect_to @todo, alert: "完了済みのToDoは編集できません" if @todo.completed?
  end

  def update
    respond_to do |format|
      if @todo.update(todo_params)
        format.html { redirect_to @todo.list, notice: "ToDoを更新しました" }
        format.json { render json: TodoResource.new(@todo) }
      else
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: { errors: @todo.errors.full_messages }, status: :unprocessable_content }
      end
    end
  end

  def destroy
    list = @todo.list
    @todo.destroy!

    respond_to do |format|
      format.html { redirect_to list, notice: "ToDoを削除しました", status: :see_other }
      format.json { head :no_content }
    end
  end

  private

  def set_todo
    @todo = Todo.find(params[:id])
  end

  # list_params と同じ理由で require/permit を使う。
  def todo_params
    params.require(:todo).permit(:title)
  end
end
