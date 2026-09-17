class ListsController < ApplicationController
  before_action :set_list, only: %i[show edit update destroy]

  def index
    @lists = List.where(archived_at: nil).order(:id)
    @archived_lists = List.where.not(archived_at: nil).order(:id)

    respond_to do |format|
      format.html
      format.json { render json: ListResource.new(List.order(:id)) }
    end
  end

  def show
    @todos = @list.todos.order(Arel.sql("completed_at IS NOT NULL"), :id)

    respond_to do |format|
      format.html
      format.json { render json: ListDetailResource.new(@list) }
    end
  end

  def new
    @list = List.new
  end

  def edit
  end

  def create
    @list = List.new(list_params)

    respond_to do |format|
      if @list.save
        format.html { redirect_to @list, notice: "リストを作成しました" }
        format.json { render json: ListResource.new(@list), status: :created, location: api_list_url(@list) }
      else
        format.html { render :new, status: :unprocessable_content }
        format.json { render json: { errors: @list.errors.full_messages }, status: :unprocessable_content }
      end
    end
  end

  def update
    respond_to do |format|
      if @list.update(list_params)
        format.html { redirect_to @list, notice: "リストを更新しました" }
        format.json { render json: ListResource.new(@list) }
      else
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: { errors: @list.errors.full_messages }, status: :unprocessable_content }
      end
    end
  end

  def destroy
    @list.destroy!

    respond_to do |format|
      format.html { redirect_to lists_path, notice: "リストを削除しました", status: :see_other }
      format.json { head :no_content }
    end
  end

  private

  def set_list
    @list = List.find(params[:id])
  end

  def list_params
    params.expect(list: [ :name ])
  end
end
