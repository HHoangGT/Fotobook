class DiscoversController < ApplicationController
  before_action :authenticate_user!, except: %i[album photo]

  def photo
    @photos = Photo.all.page(params[:page]).per(4)
    render 'feeds/feeds'
  end

  def album
    @albums = Album.all.page(params[:page]).per(4)
    render 'feeds/albums'
  end
end
