class DiscoversController < ApplicationController
  def photo
    @users = User.where.not(id: current_user.id)
    render 'feeds/feeds'
  end

  def album
    @users = User.where.not(id: current_user.id)
    render 'feeds/albums'
  end
end
