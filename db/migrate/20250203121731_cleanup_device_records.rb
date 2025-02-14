class CleanupDeviceRecords < ActiveRecord::Migration[8.0]
  def up
    # First create backup tables
    create_table :devices_backup do |t|
      t.integer :user_id
      t.string :device_id
      t.string :system_id
      t.string :fingerprint
      t.string :device_type
      t.boolean :active
      t.datetime :last_active_at
      t.json :device_info
      t.timestamps null: false
    end

    create_table :device_databases_backup do |t|
      t.integer :device_id
      t.string :path
      t.string :sync_token
      t.datetime :last_synced_at
      t.timestamps null: false
    end

    # Backup device_databases first
    execute <<-SQL
      INSERT INTO device_databases_backup 
      SELECT * FROM device_databases;
    SQL

    # Backup devices
    Device.find_each do |device|
      execute <<-SQL
        INSERT INTO devices_backup 
        (id, user_id, device_id, system_id, fingerprint, device_type, active, 
         last_active_at, device_info, created_at, updated_at)
        VALUES 
        (#{device.id}, #{device.user_id}, '#{device.device_id}', '#{device.system_id}',
         '#{device.fingerprint}', '#{device.device_type}', #{device.active ? 1 : 0},
         '#{device.last_active_at}', '#{device.device_info.to_json}',
         '#{device.created_at}', '#{device.updated_at}')
      SQL
    end

    # Clear tables in correct order
    execute "DELETE FROM device_databases"
    execute "DELETE FROM devices"

    # Reset sequences
    if ActiveRecord::Base.connection.adapter_name == 'PostgreSQL'
      execute "ALTER SEQUENCE devices_id_seq RESTART WITH 1;"
      execute "ALTER SEQUENCE device_databases_id_seq RESTART WITH 1;"
    else
      execute "DELETE FROM sqlite_sequence WHERE name IN ('devices', 'device_databases');"
    end
  end

  def down
    # Restore in correct order
    execute <<-SQL
      INSERT INTO devices 
      SELECT * FROM devices_backup;
    SQL

    execute <<-SQL
      INSERT INTO device_databases 
      SELECT * FROM device_databases_backup;
    SQL

    drop_table :device_databases_backup
    drop_table :devices_backup
  end
end
