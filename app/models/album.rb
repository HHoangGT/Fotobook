class Album < ApplicationRecord
  belongs_to :user
  has_many :liked_albums
  has_many :like_user, through: :liked_albums, source: :user
  mount_uploaders :images, ImageUploader

  validates :title, presence: true, length: { maximum: 140 }
  validates :description, presence: true, length: { maximum: 300 }
  validates :mode, presence: true, inclusion: { in: %w[Public Private], message: '%<value> is not a valid mode' }
  validates :likes, presence: true
end
