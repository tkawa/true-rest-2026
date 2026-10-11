class CommentsController < ApplicationController
  before_action :set_todo

  # JSON の経路だけ（HTML の一覧はToDoの詳細に埋め込まれる）。
  def index
    render json: CommentResource.new(@todo.comments.order(:id))
  end

  def create
    @comment = @todo.comments.build(comment_params)

    respond_to do |format|
      if @comment.save
        format.html { redirect_to @todo, notice: "コメントを追加しました", status: :see_other }
        format.json { render json: CommentResource.new(@comment), status: :created }
      else
        format.html { redirect_to @todo, alert: @comment.errors.full_messages.to_sentence, status: :see_other }
        format.json { render json: { errors: @comment.errors.full_messages }, status: :unprocessable_content }
      end
    end
  end

  private

  def set_todo
    @todo = Todo.find(params[:todo_id])
  end

  def comment_params
    params.require(:comment).permit(:body)
  end
end
