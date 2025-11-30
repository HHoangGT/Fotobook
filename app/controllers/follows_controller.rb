class FollowsController < ApplicationController
  def unfollow
    follow_record = Follow.find_by(follower_id: params[:follower_id], followed_id: params[:followed_id])
    if follow_record
      follow_record.destroy
    else
      flash[:alert] = 'There has been an error'
    end
    redirect_to request.referer
  end

  def follow
    follow_record = Follow.find_by(follower_id: params[:follower_id], followed_id: params[:followed_id])
    if follow_record
      flash[:alert] = 'You have already follow this guy'
    else
      # Follow.create(follower: User.find_by(id: params[:follower_id]), followed: User.find_by(id: params[:followed_id]))
      followed_user = User.find_by(id: params[:followed_id])
      follower_user = User.find_by(id: params[:follower_id])
      if followed_user && follower_user
        Follow.create(follower: follower_user, followed: followed_user)
        ActivityLogger.log_follow(follower_user, followed_user)
      end
    end
    redirect_to request.referer
  end
end
