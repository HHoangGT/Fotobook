class ProfilesController < ApplicationController
  def personalpagephoto
    @user = current_user
  end

  def personalpagealbum
    @user = current_user
  end

  def personalpagefollower
    @user = current_user
  end

  def personalpagefollowing
    @user = current_user
  end
end
