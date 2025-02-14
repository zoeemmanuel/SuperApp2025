module DeviceAuthenticationConcern
  extend ActiveSupport::Concern

  included do
    helper_method :current_device if respond_to?(:helper_method)
  end

  def current_device
    return @current_device if defined?(@current_device)
    
    if db_path = cookies[:device_database_path]
      if device = find_device_by_path(db_path)
        @current_device = device
        sync_device_state(device) if device.active?
      end
    end
    
    @current_device
  end

  def find_known_device(device_data)
    Rails.logger.info "Finding device with data: #{device_data.inspect}"
    Rails.logger.info "Database Path Cookie: #{cookies[:device_database_path]}"

    db_path = device_data.dig('database', 'path') || cookies[:device_database_path]
    return nil unless db_path && File.exist?(Rails.root.join(db_path))

    device_info = read_device_info(db_path)
    return nil unless device_info['device_id']

    device = Device.find_by(device_id: device_info['device_id']) ||
             Device.find_by(system_id: device_info['system_id'])

    return device if validate_device(device)
    nil
  end

  def set_device_token(device)
    return unless device&.device_database&.path

    begin
      cookie_opts = {
        secure: true,
        same_site: :lax,
        path: '/',
        domain: determine_cookie_domain,
        expires: 1.year.from_now,
        httponly: false
      }

      cookies[:device_database_path] = cookie_opts.merge(value: device.device_database.path)
      cookies[:device_token] = cookie_opts.merge(
        value: device.device_id,
        httponly: true
      )

      storage_data = {
        device_database_path: device.device_database.path,
        device_token: device.device_id,
        sync_time: Time.current.iso8601
      }
      
      response.headers['X-Set-Storage'] = storage_data.to_json

      Rails.logger.info "Set device cookies:"
      Rails.logger.info "- Token: #{device.device_id}"
      Rails.logger.info "- Database path: #{device.device_database.path}"
      Rails.logger.info "- Storage header set with: #{storage_data.inspect}"
    rescue => e
      Rails.logger.error "Failed to set device cookies: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
  end

  def process_device_data
    device_data = params[:device_data] || 
                 params.dig(:auth, :device_data) || 
                 (params.to_unsafe_h rescue {})['device_data']
                 
    return {} unless device_data.present?

    device_data = if device_data.respond_to?(:to_unsafe_h)
      device_data.to_unsafe_h
    elsif device_data.is_a?(String)
      JSON.parse(device_data) rescue {}
    else
      device_data.to_h
    end
    
    Rails.logger.info "Processing device data: #{device_data.inspect}"
    
    {
      'database' => process_database_info(device_data),
      'browser_info' => device_data.slice('hardware', 'screen', 'browser', 'gpu')
    }
  end

  def process_database_info(device_data)
    if device_data['database'].present?
      device_data['database']
    else
      db_path = cookies[:device_database_path]
      if db_path
        {
          'path' => db_path,
          'exists' => File.exist?(Rails.root.join(db_path))
        }
      else
        nil
      end
    end
  end

def create_new_device_data(browser_info)
  db_path = "devices/#{SecureRandom.uuid}/device.db"
  full_path = Rails.root.join(db_path)
  
  FileUtils.mkdir_p(File.dirname(full_path))
  db = SQLite3::Database.new(full_path.to_s)
  
  setup_database_tables(db)
  device_id = SecureRandom.uuid
  system_id = SecureRandom.uuid
  insert_initial_data(db, device_id, system_id)
  
  db.close

  {
    device_id: device_id,
    system_id: system_id,
    database_path: db_path,
    browser_info: browser_info
  }
end

def sync_new_device_data(device_data)
  set_device_cookies(device_data[:database_path])
  
  @storage_header = {
    device_database_path: device_data[:database_path],
    sync_time: Time.current.iso8601
  }.to_json
  
  response.headers['X-Set-Storage'] = @storage_header
end

def insert_initial_data(db, device_id, system_id, verified = nil)
  db.execute("INSERT OR REPLACE INTO device_info (key, value) VALUES (?, ?)", 
             ["device_id", device_id])
  db.execute("INSERT OR REPLACE INTO device_info (key, value) VALUES (?, ?)", 
             ["system_id", system_id])
  db.execute("INSERT OR REPLACE INTO device_info (key, value) VALUES (?, ?)", 
             ["verified", verified.to_s]) if verified
  db.execute("INSERT OR REPLACE INTO device_info (key, value) VALUES (?, ?)", 
             ["created_at", Time.current.iso8601])
end

def setup_database_tables(db)
  db.execute(<<-SQL)
    CREATE TABLE IF NOT EXISTS device_info (
      key TEXT PRIMARY KEY,
      value TEXT
    );
  SQL
end

  private

  def find_device_by_path(db_path)
    return nil unless File.exist?(Rails.root.join(db_path))
    
    begin
      device_info = read_device_info(db_path)
      return nil unless device_info['device_id']
      
      device = Device.find_by(device_id: device_info['device_id'])
      if device && validate_device(device)
        sync_device_state(device) if device.active?
        return device
      end
    rescue => e
      Rails.logger.error "Error finding device by path: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
    nil
  end

  def read_device_info(db_path)
    db = SQLite3::Database.new(Rails.root.join(db_path).to_s)
    db.results_as_hash = true
    device_info = db.execute("SELECT * FROM device_info")
                   .each_with_object({}) { |row, hash| hash[row['key'] || row[0]] = row['value'] || row[1] }
    db.close
    device_info
  rescue SQLite3::Exception => e
    Rails.logger.error "Failed to read device info: #{e.message}"
    {}
  end

  def validate_device(device)
    return false unless device&.device_database&.full_path
    return false unless File.exist?(device.device_database.full_path)
    
    begin
      device_info = read_device_info(device.device_database.path)
      device_info['device_id'] == device.device_id || 
      device_info['system_id'] == device.system_id
    rescue => e
      Rails.logger.error "Device validation error: #{e.message}"
      false
    end
  end

  def sync_device_state(device)
    return unless device&.device_database&.path
    
    begin
      # Set proper storage headers
      storage_data = {
        device_database_path: device.device_database.path,
        device_id: device.device_id,
        sync_time: Time.current.iso8601,
        session_active: true
      }
      response.headers['X-Set-Storage'] = storage_data.to_json

      # Set both regular and signed cookies
      cookie_opts = {
        value: device.device_database.path,
        domain: determine_cookie_domain,
        secure: true,
        same_site: :lax,
        path: '/',
        expires: 1.year.from_now,
        httponly: false
      }

      cookies[:device_database_path] = cookie_opts
      cookies.signed[:device_database_path] = cookie_opts.merge(httponly: true)

      # Update session
      session[:device_id] = device.id if device.active?

      Rails.logger.info "Synced device state:"
      Rails.logger.info "- Device ID: #{device.id}"
      Rails.logger.info "- Database path: #{device.device_database.path}"
      Rails.logger.info "- Storage header: #{storage_data.inspect}"
    rescue => e
      Rails.logger.error "Failed to sync device state: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
  end

  def determine_cookie_domain
    return request.domain if request.domain.present?
    return request.host if request.host.present?
    'localhost'
  end

  def set_device_cookies(db_path)
    return unless db_path

    cookie_opts = {
      value: db_path,
      domain: determine_cookie_domain,
      secure: true,
      same_site: :lax,
      path: '/',
      expires: 1.year.from_now,
      httponly: false
    }

    # Set both cookie versions
    cookies[:device_database_path] = cookie_opts
    cookies.signed[:device_database_path] = cookie_opts.merge(httponly: true)

    # Set storage header
    response.headers['X-Set-Storage'] = {
      device_database_path: db_path,
      sync_time: Time.current.iso8601,
      session_active: true
    }.to_json

    Rails.logger.info "Set device cookies for path: #{db_path}"
  end

  def update_device_info(device, updates = {})
    return unless device&.device_database&.path
    db_path = Rails.root.join(device.device_database.path)
    return unless File.exist?(db_path)

    begin
      db = SQLite3::Database.new(db_path.to_s)
      updates.each do |key, value|
        db.execute(
          "INSERT OR REPLACE INTO device_info (key, value) VALUES (?, ?)", 
          [key.to_s, value.to_s]
        )
      end

      db.execute(
        "INSERT OR REPLACE INTO device_info (key, value) VALUES (?, ?)",
        ["last_sync", Time.current.iso8601]
      )

      db.close
      
      Rails.logger.info "Updated device info for device #{device.id}"
      Rails.logger.info "Updates: #{updates.inspect}"
    rescue SQLite3::Exception => e
      Rails.logger.error "Database update error for device #{device.id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
  end
end
