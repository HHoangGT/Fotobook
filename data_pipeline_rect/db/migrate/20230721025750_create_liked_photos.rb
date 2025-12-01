class CreateLikedPhotos < ActiveRecord::Migration[7.0]
  def change
    create_table :liked_photos do |t|
      t.belongs_to :user, index: true, foreign_key: true
      t.belongs_to :photo, index: true, foreign_key: true

      t.timestamps
    end
  end
end
