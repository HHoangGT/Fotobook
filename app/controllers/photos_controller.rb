class PhotosController < ApplicationController
  def new
    @photo = current_user.photos.new
  end

  def create
    @photo = current_user.photos.new photo_params
    if @photo.save
      flash[:notice] = 'Update Successfully'
      redirect_to profiles_photos_path
    else
      flash[:alert] = 'There has been an error while updating image'
      redirect_to new_photo_path
    end
  end

  def edit
    @photo = Photo.find(params[:id])
  end

  def update
    @photo = Photo.find(params[:id])
    if params[:save].present?
      if @photo.update(photo_params)
        flash[:notice] = 'Uploaded successfully'
        redirect_to profiles_photos_path
      else
        flash[:alert] = 'There has been an error when uploading photo'
        redirect_to edit_photo_path
      end
    elsif params[:delete].present?
      if @photo.destroy
        flash[:notice] = 'Deleted successfully'
        redirect_to profiles_photos_path
      else
        flash[:alert] = 'There has been an error when deleting photo'
        redirect_to edit_photo_path
      end
    else
      render 'photos/edit'
    end
  end

  private

  def photo_params
    params.require(:photo).permit(:title, :description, :mode, :image)
  end
end
