class FeedsController < ApplicationController
  def photo
    @users = current_user.followings
    @photos = Photo.where(user_id: @users.pluck(:id), mode: 'Public').page(params[:page]).per(4)
    ActivityLogger.log_feed_view(current_user, 'photo')
    render 'feeds/feeds'
  end

  def album
    @users = current_user.followings
    @albums = Album.where(user_id: @users.pluck(:id), mode: 'Public').page(params[:page]).per(4)
    ActivityLogger.log_feed_view(current_user, 'album')
    render 'feeds/albums'
  end
end
