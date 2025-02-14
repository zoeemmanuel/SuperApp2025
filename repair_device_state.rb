#!/usr/bin/env ruby

Rails.application.load_console

puts "Repairing device and database state..."

def initialize_device_database(path)
  SQLite3::Database.new(path.to_s) do |db|
    db.execute(<<~SQL)
      DROP TABLE IF EXISTS device_data;
    SQL

    db.execute(<<~SQL)
      CREATE TABLE device_data (
        id INTEGER PRIMARY KEY,
        key TEXT NOT NULL,
        value TEXT,
        synced BOOLEAN DEFAULT 0,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      );
    SQL

    db.execute(<<~SQL)
      DROP TABLE IF EXISTS sync_state;
    SQL

    db.execute(<<~SQL)
      CREATE TABLE sync_state (
        id INTEGER PRIMARY KEY,
        last_sync_timestamp TEXT,
        sync_token TEXT
      );
    SQL
  end
end

def initialize_cloud_database(path)
  SQLite3::Database.new(path.to_s) do |db|
    db.execute(<<~SQL)
      DROP TABLE IF EXISTS cloud_data;
    SQL

    db.execute(<<~SQL)
      CREATE TABLE cloud_data (
        id INTEGER PRIMARY KEY,
        device_id TEXT NOT NULL,
        key TEXT NOT NULL,
        value TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      );
    SQL

    db.execute(<<~SQL)
      CREATE INDEX IF NOT EXISTS idx_cloud_data_device_id ON cloud_data(device_id);
    SQL
  end
end

ActiveRecord::Base.transaction do
  begin
    # 1. Clean up duplicate devices first
    Device.select(:fingerprint).distinct.each do |device|
      devices = Device.where(fingerprint: device.fingerprint).order(last_active_at: :desc)
      if devices.count > 1
        puts "\nFound duplicate devices for fingerprint: #{device.fingerprint}"
        most_recent = devices.first
        puts "Keeping device: #{most_recent.device_id}"
        
        devices.offset(1).each do |old_device|
          puts "Deactivating duplicate: #{old_device.device_id}"
          old_device.update!(active: false)
        end
      end
    end

    # 2. Set up device databases
    Device.where(active: true).each do |device|
      puts "\nChecking device: #{device.device_id}"
      
      db_path = Rails.root.join('db', 'devices', "#{device.device_id}.sqlite3")
      initialize_device_database(db_path)
      
      unless device.device_database
        puts "Creating database record for device #{device.device_id}"
        device.create_device_database!(
          path: db_path.to_s,
          sync_token: SecureRandom.hex(16)
        )
      end

      # Initialize sync state
      db = SQLite3::Database.new(db_path.to_s)
      db.execute(<<~SQL, [Time.current.iso8601, device.device_database.sync_token])
        INSERT INTO sync_state (last_sync_timestamp, sync_token)
        VALUES (?, ?);
      SQL
      db.close
    end

    # 3. Set up cloud databases
    User.find_each do |user|
      puts "\nChecking cloud state for user #{user.handle}"
      
      container_id = user.cloud_container_id || "user-#{user.id}-#{SecureRandom.hex(6)}"
      cloud_path = Rails.root.join('db', 'cloud_replicas', "#{user.id}.sqlite3")
      
      FileUtils.mkdir_p(Rails.root.join('db', 'cloud_replicas'))
      initialize_cloud_database(cloud_path)

      user.update!(
        cloud_container_id: container_id,
        cloud_db_path: cloud_path.to_s
      )
    end

  rescue => e
    puts "Error during repair: #{e.message}"
    puts e.backtrace
    raise e
  end
end

puts "\nRepair complete. Running final check..."

puts "\nActive devices after cleanup:"
Device.where(active: true).each do |device|
  puts "#{device.device_id} (#{device.device_type}) - #{device.fingerprint}"
  puts "Database: #{device.device_database&.path || 'None'}"
  
  if device.device_database
    db = SQLite3::Database.new(device.device_database.path)
    db.results_as_hash = true
    
    sync_state = db.execute("SELECT * FROM sync_state LIMIT 1").first
    puts "Sync State: #{sync_state.inspect}"
    db.close
  end
end

puts "\nCloud databases:"
User.find_each do |user|
  puts "#{user.handle}: #{user.cloud_db_path}"
  if user.cloud_db_path
    db = SQLite3::Database.new(user.cloud_db_path)
    count = db.execute("SELECT COUNT(*) FROM cloud_data").first[0]
    puts "Cloud data count: #{count}"
    db.close
  end
end
