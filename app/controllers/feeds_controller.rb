class FeedsController < ApplicationController
  def photo
    @users = current_user.followings
    @photos = Photo.where(user_id: @users.pluck(:id), mode: 'Public').page(params[:page]).per(4)
    render 'feeds/feeds'
  end

  def album
    @users = current_user.followings
    @albums = Album.where(user_id: @users.pluck(:id), mode: 'Public').page(params[:page]).per(4)
    render 'feeds/albums'
  end
end
