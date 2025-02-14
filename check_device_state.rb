#!/usr/bin/env ruby

Rails.application.load_console

puts "\n=== Current Device State ==="
puts "\nActive Devices:"
Device.where(active: true).each do |device|
  puts "\nDevice ID: #{device.device_id}"
  puts "Type: #{device.device_type}"
  puts "Fingerprint: #{device.fingerprint}"
  puts "Last Active: #{device.last_active_at}"
  
  if device.device_database
    puts "\nDatabase Info:"
    db = SQLite3::Database.new(device.device_database.path)
    db.results_as_hash = true
    
    puts "Data Records:"
    data = db.execute("SELECT * FROM device_data")
    puts data.inspect
    
    puts "\nSync State:"
    sync = db.execute("SELECT * FROM sync_state")
    puts sync.inspect
    
    db.close
  else
    puts "No database associated"
  end
end

puts "\n=== Cloud Database State ==="
User.find_each do |user|
  next unless user.cloud_db_path
  puts "\nUser: #{user.handle}"
  
  begin
    db = SQLite3::Database.new(user.cloud_db_path)
    db.results_as_hash = true
    
    puts "Cloud Data:"
    data = db.execute("SELECT * FROM cloud_data")
    puts data.inspect
  rescue => e
    puts "Error accessing cloud DB: #{e.message}"
  ensure
    db&.close
  end
end
