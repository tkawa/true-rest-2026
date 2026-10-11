class SubtasksController < ApplicationController
  before_action :set_todo

  # JSON の経路だけ（HTML の一覧はToDoの行と詳細に埋め込まれる）。
  def index
    render json: SubtaskResource.new(@todo.subtasks.order(:id))
  end

  def create
    @subtask = @todo.subtasks.build(subtask_params)

    respond_to do |format|
      if @subtask.save
        format.html { redirect_to @todo, notice: "サブタスクを追加しました", status: :see_other }
        format.json { render json: SubtaskResource.new(@subtask), status: :created }
      else
        format.html { redirect_to @todo, alert: @subtask.errors.full_messages.to_sentence, status: :see_other }
        format.json { render json: { errors: @subtask.errors.full_messages }, status: :unprocessable_content }
      end
    end
  end

  private

  def set_todo
    @todo = Todo.find(params[:todo_id])
  end

  def subtask_params
    params.require(:subtask).permit(:title)
  end
end
