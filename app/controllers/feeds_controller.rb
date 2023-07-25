class FeedsController < ApplicationController
  def photo
    @users = current_user.followings
    @users.each do |user|
      @photos = user.photos.page(params[:page]).per(4)
      render 'feeds/feeds'
    end
  end

  def album
    @users = current_user.followings
    @users.each do |user|
      @albums = user.albums.page(params[:page]).per(4)
      render 'feeds/albums'
    end
  end
end
