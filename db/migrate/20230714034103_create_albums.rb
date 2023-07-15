class CreateAlbums < ActiveRecord::Migration[7.0]
  def change
    create_table :albums do |t|
      t.string :title, null: false, default: ''
      t.text :description, null: false, default: ''
      t.string :mode, null: false, default: ''
      t.integer :likes, null: false, default: 0

      t.timestamps null: false

      t.belongs_to :user, index: true, foreign_key: true
    end
  end
end
