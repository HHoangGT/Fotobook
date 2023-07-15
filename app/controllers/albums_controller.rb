class AlbumsController < ApplicationController
  before_action :required_login

  def new
    @album = current_user.albums.new
  end

  def create
    @album = current_user.albums.new album_params
    if @album.save
      flash[:notice] = 'Update Successfully'
      redirect_to new_album_path
    else
      flash[:alert] = 'There has been an error while updating album'
      redirect_to new_album_path
    end
  end

  private

  def required_login
    return if user_signed_in?

    flash[:alert] = 'You must be logged in to access this section'
    redirect_to new_user_session_path
  end

  def album_params
    params.require(:album).permit(:title, :description, :mode, { images: [] })
  end
end
