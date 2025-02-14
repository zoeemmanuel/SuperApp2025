class AddDeviceInfoToDevices < ActiveRecord::Migration[8.0]
  def change
    add_column :devices, :device_info, :json
    
    # Remove uniqueness constraint from fingerprint as multiple browsers can have same hardware
    remove_index :devices, :fingerprint
    add_index :devices, :fingerprint
  end
end
