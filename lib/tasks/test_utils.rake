namespace :test_utils do
  desc "Clear all device databases and reset devices for testing"
  task reset_devices: :environment do
    puts "Starting cleanup process..."

    # Count before cleanup
    total_devices = Device.count
    total_databases = DeviceDatabase.count
    puts "Current count - Devices: #{total_devices}, Databases: #{total_databases}"

    begin
      ActiveRecord::Base.transaction do
        # Clear device databases from filesystem
        device_db_path = Rails.root.join('db', 'devices')
        if Dir.exist?(device_db_path)
          puts "Removing SQLite database files..."
          FileUtils.rm_rf(Dir.glob("#{device_db_path}/*"))
        end

        # Clear verification data
        verification_path = Rails.root.join('tmp', 'verification_data')
        if Dir.exist?(verification_path)
          puts "Clearing verification data..."
          FileUtils.rm_rf(Dir.glob("#{verification_path}/*"))
        end

        # Clear database records
        puts "Clearing database records..."
        DeviceDatabase.delete_all
        Device.delete_all

        puts "\nCleanup completed successfully!"
        puts "All devices and databases have been reset"
      end
    rescue => e
      puts "Error during cleanup: #{e.message}"
      puts e.backtrace
    end

    # Count after cleanup
    new_total_devices = Device.count
    new_total_databases = DeviceDatabase.count
    puts "\nFinal count - Devices: #{new_total_devices}, Databases: #{new_total_databases}"
  end

  desc "Test cross-browser recognition for a specific user"
  task :test_recognition, [:phone_or_handle] => :environment do |t, args|
    unless args[:phone_or_handle]
      puts "Please provide a phone number or handle"
      puts "Usage: rake test_utils:test_recognition['+447123456789']"
      puts "   or: rake test_utils:test_recognition['@username']"
      exit
    end

    identifier = args[:phone_or_handle]
    user = if identifier.start_with?('+')
      User.find_by(phone: identifier)
    else
      User.find_by(handle: identifier)
    end

    unless user
      puts "User not found with identifier: #{identifier}"
      exit
    end

    puts "\nTesting recognition for user: #{user.handle} (#{user.phone})"
    puts "Active devices: #{user.devices.active.count}"
    puts "Total devices: #{user.devices.count}"
    
    user.devices.each do |device|
      puts "\nDevice ID: #{device.id}"
      puts "Status: #{device.active ? 'Active' : 'Inactive'}"
      puts "Last active: #{device.last_active_at}"
      puts "Database path: #{device.device_database&.path}"
      puts "Browser info: #{device.device_info['browsers']}"
    end
  end

  desc "Show current device and database stats"
  task stats: :environment do
    puts "\nDevice Statistics:"
    puts "----------------"
    puts "Total Devices: #{Device.count}"
    puts "Active Devices: #{Device.where(active: true).count}"
    puts "Inactive Devices: #{Device.where(active: false).count}"
    
    puts "\nDatabase Statistics:"
    puts "------------------"
    puts "Total Device Databases: #{DeviceDatabase.count}"
    
    # Check filesystem
    device_db_path = Rails.root.join('db', 'devices')
    db_files = Dir.glob("#{device_db_path}/*.sqlite3").count if Dir.exist?(device_db_path)
    puts "SQLite Files on Disk: #{db_files || 0}"
    
    puts "\nVerification Data:"
    puts "-----------------"
    verification_path = Rails.root.join('tmp', 'verification_data')
    verification_files = Dir.glob("#{verification_path}/*.json").count if Dir.exist?(verification_path)
    puts "Verification Files: #{verification_files || 0}"
  end
end
