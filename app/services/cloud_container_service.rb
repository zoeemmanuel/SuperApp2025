class CloudContainerService
  class << self
    def create_user_container(user)
      container_id = "user-#{user.id}-#{SecureRandom.hex(6)}"
      
      # Initialize cloud storage for user
      cloud_db_path = Rails.root.join('db', 'cloud_replicas', "#{user.id}.sqlite3")
      
      # Create database directory if it doesn't exist
      FileUtils.mkdir_p(Rails.root.join('db', 'cloud_replicas'))
      
      # Initialize cloud database
      initialize_cloud_database(cloud_db_path)
      
      # Store container reference
      user.update!(
        cloud_container_id: container_id,
        cloud_db_path: cloud_db_path.to_s
      )
      
      container_id
    end

    def initialize_cloud_database(path)
      SQLite3::Database.new(path) do |db|
        # Create sync tracking table
        db.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS sync_state (
            id INTEGER PRIMARY KEY,
            device_id TEXT NOT NULL,
            last_sync_timestamp TEXT,
            change_vector TEXT
          );
        SQL

        # Create cloud data table for synced data
        db.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS cloud_data (
            id INTEGER PRIMARY KEY,
            device_id TEXT NOT NULL,
            key TEXT NOT NULL,
            value TEXT,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
          );
        SQL

        # Create indices for better performance
        db.execute("CREATE INDEX IF NOT EXISTS idx_cloud_data_device_id ON cloud_data(device_id);")
        db.execute("CREATE INDEX IF NOT EXISTS idx_sync_state_device_id ON sync_state(device_id);")
      end
    end

    def reinitialize_cloud_database(user)
      return unless user.cloud_db_path

      initialize_cloud_database(user.cloud_db_path)
    end
  end
end
