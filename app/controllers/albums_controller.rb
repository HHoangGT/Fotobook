class AlbumsController < ApplicationController
  before_action :required_login

  def new
    @album = current_user.albums.new
  end

  def create
    @album = current_user.albums.new album_params
    if @album.save
      flash[:notice] = 'Create Successfully'
      redirect_to profiles_albums_path
    else
      flash[:alert] = 'There has been an error while updating album'
      redirect_to new_album_path
    end
  end

  def edit
    @album = Album.find(params[:id])
  end

  def update
    @album = Album.find(params[:id])
    if params[:save].present?
      if @album.update(album_params)
        flash[:notice] = 'Uploaded album successfully'
        redirect_to profiles_albums_path
      else
        flash[:alert] = 'There has been an error when uploading album'
        redirect_to edit_album_path
      end
    elsif params[:delete].present?
      if @album.destroy
        flash[:notice] = 'Delete album successfully'
        redirect_to profiles_albums_path
      else
        flash[:alert] = 'There has been an error when deleting album'
        redirect_to edit_album_path
      end
    else
      render 'albums/edit'
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
