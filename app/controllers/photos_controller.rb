class PhotosController < ApplicationController
  before_action :required_login

  def new
    @photo = current_user.photos.new
  end

  def create
    @photo = current_user.photos.new photo_params
    puts @photo
    if @photo.save
      flash[:notice] = 'Update Successfully'
      redirect_to new_photo_path
    else
      flash[:alert] = 'There has been an error while updating image'
      redirect_to new_photo_path
    end
  end

  private

  def required_login
    return if user_signed_in?

    flash[:alert] = 'You must be logged in to access this section'
    redirect_to new_user_session_path
  end

  def photo_params
    params.require(:photo).permit(:title, :description, :mode, :image)
  end
end
