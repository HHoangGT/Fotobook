class AddActivateToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :activate, :boolean
    change_column_default :users, :activate, true
  end
end
