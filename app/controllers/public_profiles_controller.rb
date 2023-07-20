class PublicProfilesController < ApplicationController
  def photo
    @user = User.find_by(id: params[:id])
    render 'profiles/personalpagephoto'
  end

  def album
    @user = User.find_by(id: params[:id])
    render 'profiles/personalpagealbum'
  end

  def following
    @user = User.find_by(id: params[:id])
    render 'profiles/personalpagefollowing'
  end

  def follower
    @user = User.find_by(id: params[:id])
    render 'profiles/personalpagefollower'
  end
end
