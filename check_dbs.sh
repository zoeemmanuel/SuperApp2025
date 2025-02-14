#!/bin/bash

echo "Checking Database States"
echo "======================="

echo "1. Checking Active Devices..."
rails runner '
  puts "Active Devices:"
  Device.active.each do |d|
    puts "ID: #{d.device_id}"
    puts "Type: #{d.device_type}"
    puts "Last Active: #{d.last_active_at}"
    puts "Fingerprint: #{d.fingerprint}"
    puts "---"
  end
'

echo "2. Checking Device Databases..."
rails runner '
  Dir.glob("db/devices/*.sqlite3").each do |db_path|
    puts "\nChecking #{db_path}"
    begin
      db = SQLite3::Database.new(db_path)
      db.results_as_hash = true
      
      puts "\nDevice Data:"
      data = db.execute("SELECT * FROM device_data")
      puts data.inspect
      
      puts "\nSync State:"
      sync = db.execute("SELECT * FROM sync_state")
      puts sync.inspect
    rescue => e
      puts "Error: #{e.message}"
    ensure
      db&.close
    end
  end
'

echo "3. Checking Cloud Database..."
rails runner '
  User.find_each do |user|
    next unless user.cloud_db_path
    puts "\nChecking cloud DB for user #{user.handle}"
    begin
      db = SQLite3::Database.new(user.cloud_db_path)
      db.results_as_hash = true
      
      puts "\nCloud Data:"
      data = db.execute("SELECT * FROM cloud_data")
      puts data.inspect
    rescue => e
      puts "Error: #{e.message}"
    ensure
      db&.close
    end
  end
'
