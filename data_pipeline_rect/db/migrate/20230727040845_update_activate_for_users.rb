class UpdateActivateForUsers < ActiveRecord::Migration[7.0]
  def change
    User.update_all(activate: true)
  end
end
