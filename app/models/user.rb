class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
  mount_uploader :avatar, AvatarUploader

  has_many :photos, dependent: :destroy
  has_many :albums, dependent: :destroy

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
