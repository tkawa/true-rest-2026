class Todos::CompletionsController < ApplicationController
  before_action :set_todo

  def create
    @todo.complete!
    respond_with_todo(notice: "ToDoを完了しました")
  end

  def destroy
    @todo.reopen!
    respond_with_todo(notice: "ToDoを再開しました")
  end

  private

  def set_todo
    @todo = Todo.find(params[:todo_id])
  end

  def respond_with_todo(notice:)
    respond_to do |format|
      format.html { redirect_to @todo.list, notice: notice, status: :see_other }
      format.json { render json: TodoResource.new(@todo) }
    end
  end
end
