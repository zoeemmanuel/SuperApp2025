#!/usr/bin/env ruby

require 'sqlite3'

def check_device_db(path)
  puts "\nChecking device database: #{path}"
  db = SQLite3::Database.new(path)
  db.results_as_hash = true
  
  puts "\nDevice Data:"
  data = db.execute("SELECT * FROM device_data LIMIT 5")
  puts data.inspect
  
  puts "\nSync State:"
  sync = db.execute("SELECT * FROM sync_state LIMIT 1")
  puts sync.inspect
rescue SQLite3::Exception => e
  puts "Error accessing database: #{e.message}"
ensure
  db&.close
end

def check_cloud_db(path)
  puts "\nChecking cloud database: #{path}"
  db = SQLite3::Database.new(path)
  db.results_as_hash = true
  
  puts "\nCloud Data:"
  data = db.execute("SELECT * FROM cloud_data LIMIT 5")
  puts data.inspect
rescue SQLite3::Exception => e
  puts "Error accessing database: #{e.message}"
ensure
  db&.close
end

# Check active devices
puts "\nActive Devices:"
system("rails runner 'puts Device.active.map { |d| [d.device_id, d.device_type, d.last_active_at] }'")

# Check device databases
Dir.glob("db/devices/*.sqlite3").each do |db_path|
  check_device_db(db_path)
end

# Check cloud databases
Dir.glob("db/cloud_replicas/*.sqlite3").each do |db_path|
  check_cloud_db(db_path)
end
