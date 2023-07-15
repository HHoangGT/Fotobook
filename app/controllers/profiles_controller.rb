class ProfilesController < ApplicationController
  before_action :required_login

  def personalpagephoto
    @user = current_user
  end

  def personalpagealbum
    @user = current_user
  end

  private

  def required_login
    return if user_signed_in?

    flash[:alert] = 'You must be logged in to access this section'
    redirect_to new_user_session_path
  end
end
