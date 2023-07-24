class AlbumsController < ApplicationController
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

  def like
    @album = Album.find(params[:album_id])
    @user = User.find(params[:user_id])
    @user.like(@album, 'album')
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: private_stream
      end
    end
  end

  private

  def private_stream
    private_target = "#{helpers.dom_id(@album)} private_likes"
    turbo_stream.replace(private_target, partial: 'feeds/partials/likes',
                                         locals: { photo: @album, type: 'album',
                                                   like_status: current_user.liked?(@album, 'album') })
  end

  def album_params
    params.require(:album).permit(:title, :description, :mode, { images: [] })
  end
end
