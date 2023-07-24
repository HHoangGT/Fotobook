class Album < ApplicationRecord
  belongs_to :user
  has_many :albulm_likeables, dependent: :destroy
  has_many :likes, through: :albulm_likeables, source: :user
  mount_uploaders :images, ImageUploader

  validates :title, presence: true, length: { maximum: 140 }
  validates :description, presence: true, length: { maximum: 300 }
  validates :mode, presence: true, inclusion: { in: %w[Public Private], message: '%<value> is not a valid mode' }
end
