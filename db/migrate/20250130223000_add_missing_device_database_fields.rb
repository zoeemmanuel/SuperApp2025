class AddMissingDeviceDatabaseFields < ActiveRecord::Migration[8.0]
  def change
    create_table :device_databases do |t|
      t.references :device, null: false, foreign_key: true
      t.string :path, null: false
      t.string :sync_token, null: false
      t.datetime :last_synced_at
      t.timestamps
    end

    add_index :device_databases, :path, unique: true
    add_index :device_databases, :sync_token, unique: true
  end
end
