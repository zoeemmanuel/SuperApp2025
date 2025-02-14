class ReplicationService
  class << self
    def sync_device(device)
      return error_response('No local database') unless device.local_db_path
      return error_response('No cloud database') unless device.user.cloud_db_path

      ActiveRecord::Base.transaction do
        begin
          local_db = SQLite3::Database.new(device.local_db_path)
          cloud_db = SQLite3::Database.new(device.user.cloud_db_path)

          local_db.results_as_hash = true
          cloud_db.results_as_hash = true

          sync_result = perform_sync(device, local_db, cloud_db)
          
          if sync_result[:status] == 'success'
            device.device_database.update!(last_synced_at: Time.current)
          end

          sync_result
        rescue SQLite3::Exception => e
          handle_sqlite_error(e, device)
        rescue StandardError => e
          handle_general_error(e, device)
        ensure
          local_db&.close
          cloud_db&.close
        end
      end
    end

    private

    def perform_sync(device, local_db, cloud_db)
      local_db.transaction do
        cloud_db.transaction do
          sync_to_cloud(device, local_db, cloud_db)
          sync_from_cloud(device, local_db, cloud_db)
          
          # Update sync state
          local_db.execute(<<~SQL, [Time.current.iso8601])
            UPDATE sync_state 
            SET last_sync_timestamp = ?
            WHERE id = 1;
          SQL

          { status: 'success', synced_at: Time.current }
        end
      end
    end

    def sync_to_cloud(device, local_db, cloud_db)
      changes = local_db.execute(<<~SQL)
        SELECT * FROM device_data 
        WHERE synced = 0
        ORDER BY created_at ASC;
      SQL

      changes.each do |change|
        sql = <<~SQL
          INSERT INTO cloud_data
          (device_id, key, value, created_at)
          VALUES (?, ?, ?, ?);
        SQL
        
        cloud_db.execute(sql, [
          device.device_id,
          change['key'],
          change['value'],
          change['created_at']
        ])
      end

      # Mark as synced
      local_db.execute(<<~SQL)
        UPDATE device_data 
        SET synced = 1 
        WHERE synced = 0;
      SQL
    end

    def sync_from_cloud(device, local_db, cloud_db)
      sync_state = local_db.execute("SELECT * FROM sync_state LIMIT 1").first
      last_sync = sync_state ? sync_state['last_sync_timestamp'] : '1970-01-01'

      cloud_changes = cloud_db.execute(<<~SQL, [device.device_id, last_sync])
        SELECT * FROM cloud_data 
        WHERE device_id != ?
        AND created_at > ?
        ORDER BY created_at ASC;
      SQL

      cloud_changes.each do |change|
        sql = <<~SQL
          INSERT OR REPLACE INTO device_data 
          (key, value, synced, created_at) 
          VALUES (?, ?, ?, ?);
        SQL
        
        local_db.execute(sql, [
          change['key'],
          change['value'],
          1,
          change['created_at']
        ])
      end
    end

    def error_response(message)
      { status: 'error', message: message }
    end

    def handle_sqlite_error(error, device)
      Rails.logger.error "SQLite error for device #{device.device_id}: #{error.message}"
      error_response("Database error: #{error.message}")
    end

    def handle_general_error(error, device)
      Rails.logger.error "Sync error for device #{device.device_id}: #{error.message}\n#{error.backtrace.join("\n")}"
      error_response("Internal sync error")
    end
  end
end
