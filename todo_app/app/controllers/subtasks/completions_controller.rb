class Subtasks::CompletionsController < ApplicationController
  before_action :set_subtask

  def create
    @subtask.complete!
    respond_with_subtask(notice: "サブタスクを完了しました")
  end

  def destroy
    @subtask.reopen!
    respond_with_subtask(notice: "サブタスクを再開しました")
  end

  private

  def set_subtask
    @subtask = Subtask.find(params[:subtask_id])
  end

  def respond_with_subtask(notice:)
    respond_to do |format|
      format.html { redirect_to @subtask.todo.list, notice: notice, status: :see_other }
      format.json { render json: SubtaskResource.new(@subtask) }
    end
  end
end
