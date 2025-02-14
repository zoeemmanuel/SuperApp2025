class UpdateDeviceDatabases < ActiveRecord::Migration[7.0]
  def change
    # Add columns to the device_databases table
    add_column :device_databases, :last_sync_timestamp, :datetime, null: true
    add_column :device_databases, :sync_status, :string
    add_index :device_databases, :last_sync_timestamp
    
    # Add sync_token if it doesn't exist
    unless column_exists?(:device_databases, :sync_token)
      add_column :device_databases, :sync_token, :string
    end
  end
end
