class FeedsController < ApplicationController
  def photo
    @users = current_user.followings
    render 'feeds/feeds'
  end

  def album
    @users = current_user.followings
    render 'feeds/albums'
  end
end
