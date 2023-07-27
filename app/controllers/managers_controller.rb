class ManagersController < ApplicationController
  def photo
    @photos = []
    Photo.find_each(batch_size: 100) do |photo|
      @photos << photo
    end
    @photos = Kaminari.paginate_array(@photos).page(params[:page]).per(40)
  end

  def album
    @albums = []
    Album.find_each(batch_size: 100) do |album|
      @albums << album
    end
    @albums = Kaminari.paginate_array(@albums).page(params[:page]).per(40)
  end

  def user
    @current_user_id = current_user.id
    @users = User.where.not(id: @current_user_id).pluck(:fname, :lname, :email, :last_sign_in_at, :id)
    @users = Kaminari.paginate_array(@users).page(params[:page]).per(40)
  end

  def edit
    @user = User.find_by(id: params[:user_id])
  end

  def update
    @user = User.find_by(id: params[:user_id])
    if params[:password].blank?
      if @user.update(user_without_password_params)
        flash[:notice] = 'Uploaded successfully'
      else
        flash[:alert] = 'Update Failed'
      end
    else
      @user.update(user_params)
      flash[:notice] = 'Uploaded successfully'
    end
    redirect_to request.referer
  end

  def delete
    @user = User.find_by(id: params[:user_id])
    if @user.destroy
      flash[:notice] = 'Delete successfully'
    else
      flash[:alert] = 'Cannot delete user'
    end
    redirect_to request.referer
  end

  private

  def user_without_password_params
    params.require(:user).permit(:fname, :lname, :email, :activate)
  end

  def user_params
    params.require(:user).permit(:fname, :lname, :email, :password, :activate)
  end
end
