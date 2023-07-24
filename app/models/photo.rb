class Photo < ApplicationRecord
  belongs_to :user
  has_many :liked_photos
  has_many :like_user, through: :liked_photos, source: :user
  mount_uploader :image, ImageUploader

  validates :title, presence: true, length: { maximum: 140 }
  validates :description, presence: true, length: { maximum: 300 }
  validates :mode, presence: true, inclusion: { in: %w[Public Private], message: '%<value> is not a valid mode' }
  validates :likes, presence: true
end
