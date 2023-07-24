class PhotoLikeable < ApplicationRecord
  belongs_to :user
  belongs_to :photo
end
