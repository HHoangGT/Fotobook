class DiscoversController < ApplicationController
  before_action :authenticate_user!, except: %i[album photo]

  def photo
    @photos = if user_signed_in?
                Photo.where.not(user_id: current_user.id).where(mode: 'Public').page(params[:page]).per(4)
              else
                Photo.where(mode: 'Public').page(params[:page]).per(4)
              end
    render 'feeds/feeds'
  end

  def album
    @albums = if user_signed_in?
                Album.where.not(user_id: current_user.id).where(mode: 'Public').page(params[:page]).per(4)
              else
                Album.where(mode: 'Public').page(params[:page]).per(4)
              end
    render 'feeds/albums'
  end
end
