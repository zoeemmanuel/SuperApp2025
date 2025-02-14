class DeviceService
  class << self
    def setup_device_database(device)
      return if device.device_database.present?
      
      Rails.logger.info "Setting up device database for device: #{device.id}"
      
      begin
        db_path = generate_database_path(device)
        sync_token = SecureRandom.uuid
        
        DeviceDatabase.create!(
          device: device,
          path: db_path,
          sync_token: sync_token
        )
        
        initialize_database(db_path, device)
        Rails.logger.info "Device database initialized at: #{db_path}"
        
        true
      rescue => e
        Rails.logger.error "Failed to setup device database: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        false
      end
    end

    def find_device_by_database(device_data)
      return nil unless device_data.is_a?(Hash)
      
      database_info = device_data['database'] || {}
      db_path = database_info['path']
      
      return nil unless db_path.present?
      
      begin
        Rails.logger.info "Looking for device with database path: #{db_path}"
        device_database = DeviceDatabase.find_by(path: db_path)
        return nil unless device_database&.device
        
        if verify_database_integrity(device_database)
          sync_device_info(device_database.device, device_data)
          device_database.device
        else
          Rails.logger.error "Database integrity check failed for path: #{db_path}"
          nil
        end
      rescue => e
        Rails.logger.error "Error finding device by database: #{e.message}"
        nil
      end
    end

    def register_device(user, device_data)
      Rails.logger.info "Registering new device for user: #{user.id}"
      
      device_id = SecureRandom.uuid
      system_id = SecureRandom.uuid
      
      device = Device.new(
        user: user,
        device_id: device_id,
        system_id: system_id,
        device_type: detect_device_type(device_data),
        device_info: build_device_info(device_data),
        active: true,
        last_active_at: Time.current
      )

      if device.save
        setup_device_database(device)
        device
      else
        Rails.logger.error "Failed to register device: #{device.errors.full_messages}"
        nil
      end
    end

    private

    def detect_device_type(device_data)
      return 'desktop' unless device_data.is_a?(Hash)

      ua = device_data.dig('browser', 'userAgent').to_s.downcase
      screen_width = device_data.dig('screen', 'width').to_i

      if ua =~ /mobile|android|iphone|ipod/i || screen_width < 768
        'mobile'
      elsif ua =~ /ipad|tablet/i || screen_width < 1024
        'tablet'
      else
        'desktop'
      end
    end

    def build_device_info(device_data)
      return { 'created_at' => Time.current.iso8601 } unless device_data.is_a?(Hash)

      {
        'created_at' => Time.current.iso8601,
        'platform' => device_data.dig('hardware', 'platform'),
        'model' => device_data.dig('hardware', 'model'),
        'screen' => device_data['screen'],
        'browsers' => [],
        'specs' => {
          'cpuCores' => device_data.dig('hardware', 'cpuCores'),
          'memory' => device_data.dig('hardware', 'memory')
        }.compact
      }.compact
    end

    def generate_database_path(device)
      timestamp = Time.current.strftime('%Y%m%d%H%M%S')
      File.join('db', 'devices', "device_#{device.id}_#{timestamp}.sqlite3")
    end

    def initialize_database(db_path, device)
      full_path = Rails.root.join(db_path)
      FileUtils.mkdir_p(File.dirname(full_path))
      
      begin
        db = SQLite3::Database.new(full_path.to_s)
        
        # Create tables
        create_database_tables(db)
        
        # Initialize device info
        initialize_device_info(db, device)
        
        db.close
      rescue => e
        Rails.logger.error "Database initialization failed: #{e.message}"
        raise
      end
    end

    def create_database_tables(db)
      db.execute <<-SQL
        CREATE TABLE IF NOT EXISTS device_info (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );
      SQL
      
      db.execute <<-SQL
        CREATE TABLE IF NOT EXISTS sync_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sync_time DATETIME DEFAULT CURRENT_TIMESTAMP,
          status TEXT NOT NULL
        );
      SQL
      
      db.execute <<-SQL
        CREATE TABLE IF NOT EXISTS browser_tokens (
          token TEXT PRIMARY KEY,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );
      SQL
    end

    def initialize_device_info(db, device)
      db.execute("INSERT INTO device_info (key, value) VALUES (?, ?)", 
        ["created_at", Time.current.iso8601])
      db.execute("INSERT INTO device_info (key, value) VALUES (?, ?)", 
        ["device_id", device.device_id])
      db.execute("INSERT INTO device_info (key, value) VALUES (?, ?)", 
        ["system_id", device.system_id])
    end

    def verify_database_integrity(device_database)
      return false unless device_database&.path
      
      begin
        full_path = Rails.root.join(device_database.path)
        return false unless File.exist?(full_path)
        
        db = SQLite3::Database.new(full_path.to_s)
        tables = db.execute("SELECT name FROM sqlite_master WHERE type='table';").flatten
        
        # Check required tables
        required_tables = ['device_info', 'sync_log', 'browser_tokens']
        unless required_tables.all? { |table| tables.include?(table) }
          Rails.logger.error "Missing required tables in database: #{full_path}"
          return false
        end
        
        # Verify device info
        device_info = db.execute("SELECT * FROM device_info WHERE key IN ('created_at', 'device_id', 'system_id')")
        unless device_info.size >= 3
          Rails.logger.error "Missing required device info in database: #{full_path}"
          return false
        end
        
        db.close
        true
      rescue SQLite3::Exception => e
        Rails.logger.error "Database integrity check failed: #{e.message}"
        false
      end
    end

    def sync_device_info(device, device_data)
      return unless device_data.is_a?(Hash) && device_data['browser'].present?
      
      # Update last active timestamp
      device.update!(last_active_at: Time.current)
      
      # Add browser info if new
      if device_data.dig('browser', 'userAgent').present?
        device.add_browser!(
          device_data['browser']['userAgent'],
          device_data['browser']
        )
      end
    end
  end
end
