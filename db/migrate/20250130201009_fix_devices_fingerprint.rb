class FixDevicesFingerprint < ActiveRecord::Migration[8.0]
  def change
    reversible do |dir|
      dir.up do
        # First remove any existing index if it exists
        if index_exists?(:devices, :fingerprint)
          remove_index :devices, :fingerprint
        end
        
        # Drop the column if it exists
        if column_exists?(:devices, :fingerprint)
          remove_column :devices, :fingerprint
        end
        
        # Add the column fresh
        add_column :devices, :fingerprint, :string
        add_index :devices, :fingerprint, unique: true
      end

      dir.down do
        remove_index :devices, :fingerprint
        remove_column :devices, :fingerprint
      end
    end
  end
end
