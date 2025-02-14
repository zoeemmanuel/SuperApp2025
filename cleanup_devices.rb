#!/usr/bin/env ruby

puts "Cleaning up devices..."

# Run in rails console
Rails.application.load_console

# Keep only the most recent device active per hardware fingerprint
Device.transaction do
  puts "\nBefore cleanup:"
  Device.where(active: true).each do |d|
    puts "#{d.device_id} (#{d.device_type}) - #{d.fingerprint}"
  end

  Device.select(:fingerprint).distinct.each do |device|
    devices = Device.where(fingerprint: device.fingerprint).order(last_active_at: :desc)
    if devices.count > 1
      # Keep the most recent active
      devices.offset(1).update_all(active: false)
    end
  end

  puts "\nAfter cleanup:"
  Device.where(active: true).each do |d|
    puts "#{d.device_id} (#{d.device_type}) - #{d.fingerprint}"
  end
end
