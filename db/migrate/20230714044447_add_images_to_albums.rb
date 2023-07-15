class AddImagesToAlbums < ActiveRecord::Migration[7.0]
  def change
    add_column :albums, :images, :json
  end
end
