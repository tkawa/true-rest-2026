class Lists::ArchivesController < ApplicationController
  before_action :set_list

  def create
    @list.archive!
    respond_with_list(notice: "リストをアーカイブしました")
  end

  def destroy
    @list.unarchive!
    respond_with_list(notice: "リストのアーカイブを解除しました")
  end

  private

  def set_list
    @list = List.find(params[:list_id])
  end

  def respond_with_list(notice:)
    respond_to do |format|
      format.html { redirect_to @list, notice: notice, status: :see_other }
      format.json { render json: ListResource.new(@list) }
    end
  end
end
