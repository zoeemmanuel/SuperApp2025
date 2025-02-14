class CleanupDuplicateDevices < ActiveRecord::Migration[7.0]
  def up
    Device.transaction do
      # Group devices by fingerprint
      Device.group(:fingerprint).having('COUNT(*) > 1').pluck(:fingerprint).each do |fingerprint|
        devices = Device.where(fingerprint: fingerprint).order(last_active_at: :desc)
        
        # Keep the most recently active device
        keep_device = devices.first
        
        # Deactivate and mark others as duplicates
        devices.offset(1).each do |device|
          device.update!(
            active: false,
            system_id: "#{device.system_id}_duplicate"
          )
        end
      end
    end
  end

  def down
    # This migration cannot be reversed
  end
end
