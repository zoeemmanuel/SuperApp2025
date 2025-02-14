#!/usr/bin/env ruby

Rails.application.load_console

def add_test_data(device)
  puts "\nAdding test data to device: #{device.device_id}"
  db = SQLite3::Database.new(device.device_database.path)
  db.results_as_hash = true

  # Add some test data
  db.execute(<<~SQL, ["key_#{SecureRandom.hex(4)}", "value_#{SecureRandom.hex(4)}", Time.current.iso8601])
    INSERT INTO device_data (key, value, synced, created_at)
    VALUES (?, ?, 0, ?);
  SQL

  puts "Current device data:"
  data = db.execute("SELECT * FROM device_data")
  puts data.inspect
  db.close
end

def sync_device(device)
  puts "\nSyncing device: #{device.device_id}"
  result = ReplicationService.sync_device(device)
  puts "Sync result: #{result.inspect}"

  # Check cloud state
  cloud_db = SQLite3::Database.new(device.user.cloud_db_path)
  cloud_db.results_as_hash = true
  
  puts "\nCloud data after sync:"
  cloud_data = cloud_db.execute("SELECT * FROM cloud_data")
  puts cloud_data.inspect
  cloud_db.close

  # Check device state
  device_db = SQLite3::Database.new(device.device_database.path)
  device_db.results_as_hash = true
  
  puts "\nDevice data after sync:"
  device_data = device_db.execute("SELECT * FROM device_data")
  puts device_data.inspect
  
  puts "\nSync state:"
  sync_state = device_db.execute("SELECT * FROM sync_state")
  puts sync_state.inspect
  device_db.close
end

# Test with each active device
Device.where(active: true).each do |device|
  puts "\n=== Testing device: #{device.device_id} ==="
  add_test_data(device)
  sync_device(device)
end
