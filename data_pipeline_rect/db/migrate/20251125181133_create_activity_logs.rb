class CreateActivityLogs < ActiveRecord::Migration[7.0]
  def change
    create_table :activity_logs do |t|
      t.bigint :user_id, null: false
      t.string :action, null: false
      t.string :target_type
      t.bigint :target_id
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :activity_logs, :user_id
    add_index :activity_logs, :action
    add_index :activity_logs, [:target_type, :target_id]
    add_index :activity_logs, [:user_id, :action, :created_at], name: 'index_activity_logs_on_user_action_created'
    add_index :activity_logs, :created_at
  end
end
