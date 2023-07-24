class CreatePhotoLikeables < ActiveRecord::Migration[7.0]
  def change
    create_table :photo_likeables do |t|
      t.belongs_to :user, null: false, foreign_key: true
      t.belongs_to :photo, null: false, foreign_key: true

      t.timestamps
    end
  end
end
