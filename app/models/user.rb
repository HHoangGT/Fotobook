class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :trackable
  mount_uploader :avatar, AvatarUploader

  has_many :photos, dependent: :destroy
  has_many :albums, dependent: :destroy

  has_many :photo_likeables, dependent: :destroy
  has_many :likes_photos, through: :photo_likeables, source: :photo
  has_many :albulm_likeables, dependent: :destroy
  has_many :likes_albums, through: :albulm_likeables, source: :album

  def liked?(tweet, tweet_type)
    if tweet_type == 'photo'
      likes_photos.include?(tweet)
    elsif tweet_type == 'album'
      likes_albums.include?(tweet)
    end
  end

  def like(tweet, tweet_type)
    if tweet_type == 'photo'
      if likes_photos.include?(tweet)
        likes_photos.destroy(tweet)
      else
        likes_photos << tweet
      end
    elsif tweet_type == 'album'
      if likes_albums.include?(tweet)
        likes_albums.destroy(tweet)
      else
        likes_albums << tweet
      end
    end
  end

  # For users being followed
  has_many :followers_relationships, foreign_key: :followed_id, class_name: 'Follow', dependent: :destroy
  has_many :followers, through: :followers_relationships, source: :follower

  # For users who are following
  has_many :followings_relationships, foreign_key: :follower_id, class_name: 'Follow', dependent: :destroy
  has_many :followings, through: :followings_relationships, source: :followed

  validates :fname, presence: true, length: { maximum: 25 }
  validates :lname, presence: true, length: { maximum: 25 }
  validates :email, presence: true, length: { maximum: 255 }
  validates :role, presence: true
end
