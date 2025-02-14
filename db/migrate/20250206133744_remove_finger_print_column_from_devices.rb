class RemoveFingerPrintColumnFromDevices < ActiveRecord::Migration[8.0]
  def up
    if index_exists?(:devices, :fingerprint)
      remove_index :devices, :fingerprint
    end
    
    if column_exists?(:devices, :fingerprint)
      remove_column :devices, :fingerprint
    end
  end

  def down
    unless column_exists?(:devices, :fingerprint)
      add_column :devices, :fingerprint, :string
      add_index :devices, :fingerprint, unique: true
    end
  end
end
