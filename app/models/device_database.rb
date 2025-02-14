class DeviceDatabase < ApplicationRecord
  belongs_to :device
  
  validates :path, presence: true, uniqueness: true
  validates :sync_token, presence: true, uniqueness: true
  
  after_create :initialize_database
  before_destroy :cleanup_database

  def register_browser_token(token)
    return false unless File.exist?(full_path)
    
    begin
      db = SQLite3::Database.new(full_path)
      db.execute("INSERT INTO device_info (key, value) VALUES (?, ?)", 
        ["browser_token_#{Time.current.to_i}", token])
      true
    rescue SQLite3::Exception => e
      Rails.logger.error "Error registering browser token: #{e.message}"
      false
    ensure
      db&.close
    end
  end
  
  def last_sync_timestamp
    return nil unless File.exist?(full_path)
    
    begin
      db = SQLite3::Database.new(full_path)
      db.results_as_hash = true
      
      result = db.get_first_row("SELECT last_sync FROM sync_state ORDER BY id DESC LIMIT 1")
      result && result['last_sync']
    rescue SQLite3::Exception => e
      Rails.logger.error "Error reading last sync timestamp: #{e.message}"
      nil
    ensure
      db&.close
    end
  end
  
  def full_path
    Rails.root.join(path).to_s
  end
  
  def mark_synced!
    update!(last_synced_at: Time.current)
    
    begin
      db = SQLite3::Database.new(full_path)
      db.execute("UPDATE sync_state SET last_sync = ? WHERE id = (SELECT id FROM sync_state ORDER BY id DESC LIMIT 1)",
                [Time.current.iso8601])
    rescue SQLite3::Exception => e
      Rails.logger.error "Error updating sync state: #{e.message}"
    ensure
      db&.close
    end
  end
  
  def verified_for_browser?(browser_token)
    return false unless File.exist?(full_path)
    
    begin
      db = SQLite3::Database.new(full_path)
      db.results_as_hash = true
      result = db.get_first_row("SELECT COUNT(*) as count FROM device_info WHERE key LIKE 'browser_token_%' AND value = ?", [browser_token])
      result && result['count'].to_i > 0
    rescue SQLite3::Exception => e
      Rails.logger.error "Error verifying browser token: #{e.message}"
      false
    ensure
      db&.close
    end
  end
  
  private
  
  def initialize_database
    return if File.exist?(full_path)
    
    FileUtils.mkdir_p(File.dirname(full_path))
    
    begin
      db = SQLite3::Database.new(full_path)
      
      # Create device data table
      db.execute(<<-SQL)
        CREATE TABLE IF NOT EXISTS device_data (
          id INTEGER PRIMARY KEY,
          key TEXT NOT NULL,
          value TEXT,
          synced BOOLEAN DEFAULT 0,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );
      SQL
      
      # Create sync state table
      db.execute(<<-SQL)
        CREATE TABLE IF NOT EXISTS sync_state (
          id INTEGER PRIMARY KEY,
          last_sync TEXT,
          sync_token TEXT
        );
      SQL
      
      # Create device info table for browser tokens
      db.execute(<<-SQL)
        CREATE TABLE IF NOT EXISTS device_info (
          id INTEGER PRIMARY KEY,
          key TEXT NOT NULL,
          value TEXT,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );
      SQL
      
      # Create indexes
      db.execute("CREATE INDEX IF NOT EXISTS idx_device_data_key ON device_data(key);")
      db.execute("CREATE INDEX IF NOT EXISTS idx_device_data_synced ON device_data(synced);")
      db.execute("CREATE INDEX IF NOT EXISTS idx_device_info_key ON device_info(key);")
      
      # Insert initial sync state
      db.execute(<<-SQL, [Time.current.iso8601, sync_token])
        INSERT INTO sync_state (last_sync, sync_token) 
        VALUES (?, ?);
      SQL
      
    rescue SQLite3::Exception => e
      Rails.logger.error "Database initialization error: #{e.message}"
      cleanup_database
      raise
    ensure
      db&.close
    end
  end
  
  def cleanup_database
    return unless File.exist?(full_path)
    
    begin
      File.delete(full_path)
      Rails.logger.info "Successfully deleted database file: #{full_path}"
    rescue StandardError => e
      Rails.logger.error "Error deleting database file: #{e.message}"
    end
  end
end
