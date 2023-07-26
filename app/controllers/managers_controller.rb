class ManagersController < ApplicationController
  def photo
    @photos = []
    Photo.find_each(batch_size: 100) do |photo|
      @photos << photo
    end
    @photos = Kaminari.paginate_array(@photos).page(params[:page]).per(40)
  end

  def album; end

  def user; end
end
