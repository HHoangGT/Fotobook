class CreateLikedAlbums < ActiveRecord::Migration[7.0]
  def change
    create_table :liked_albums do |t|
      t.belongs_to :user, index: true, foreign_key: true
      t.belongs_to :album, index: true, foreign_key: true

      t.timestamps
    end
  end
end
