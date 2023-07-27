class PhotosController < ApplicationController
  def new
    @photo = current_user.photos.new
  end

  def create
    @photo = current_user.photos.build photo_params
    if @photo.save
      flash[:notice] = 'Update Successfully'
      redirect_to profiles_photos_path
    else
      # flash[:alert] = 'There has been an error while updating image'
      flash[:alert] = @photo.errors.full_messages
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
        if current_user.role == 'manager'
          redirect_to manage_photo_path
        else
          redirect_to profiles_photos_path
        end
      else
        flash[:alert] = 'There has been an error when uploading photo'
        redirect_to edit_photo_path
      end
    elsif params[:delete].present?
      if @photo.destroy
        flash[:notice] = 'Deleted successfully'
        if current_user.role == 'manager'
          redirect_to manage_photo_path
        else
          redirect_to profiles_photos_path
        end
      else
        flash[:alert] = 'There has been an error when deleting photo'
        redirect_to edit_photo_path
      end
    else
      render 'photos/edit'
    end
  end

  def like
    @photo = Photo.find(params[:photo_id])
    @user = User.find(params[:user_id])
    @user.like(@photo, 'photo')
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: private_stream
      end
    end
  end

  private

  def private_stream
    private_target = "#{helpers.dom_id(@photo)} private_likes"
    turbo_stream.replace(private_target, partial: 'feeds/partials/likes',
                                         locals: { photo: @photo, type: 'photo',
                                                   like_status: current_user.liked?(@photo, 'photo') })
  end

  def photo_params
    params.require(:photo).permit(:title, :description, :mode, :image)
  end
end
