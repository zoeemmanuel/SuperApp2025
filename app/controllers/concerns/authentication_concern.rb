module AuthenticationConcern
  extend ActiveSupport::Concern

  included do
    helper_method :current_user
    helper_method :current_device
  end

def current_user
  return @current_user if defined?(@current_user)
  
  # Only check session if we have a device token
  if cookies[:device_token].present? && session[:user_id].present?
    if cookies[:device_database_path].present?
      db_path = cookies[:device_database_path]
      if File.exist?(Rails.root.join(db_path))
        begin
          db = SQLite3::Database.new(Rails.root.join(db_path).to_s)
          db.results_as_hash = true
          device_info = db.execute("SELECT * FROM device_info")
                        .each_with_object({}) { |row, hash| hash[row['key']] = row['value'] }
          db.close

          if device_info['device_id'] && device_info['verified'] == 'true'
            device = Device.find_by(device_id: device_info['device_id'])
            if device&.active?
              @current_device = device
              @current_user = device.user
            end
          end
        rescue SQLite3::Exception => e
          Rails.logger.error "Database read error: #{e.message}"
        end
      end
    end
    
    @current_user ||= User.find_by(id: session[:user_id])
  end
  
  @current_user
end

def current_device
  return @current_device if defined?(@current_device)
  
  if cookies[:device_database_path].present?
    db_path = cookies[:device_database_path]
    if File.exist?(Rails.root.join(db_path))
      device_info = read_device_info(db_path)
      if device_info['device_id']
        # Find device without checking active status
        device = Device.unscoped.find_by(device_id: device_info['device_id'])
        if device
          @current_device = device
          return device # Return device regardless of active status for GUID flow
        end
      end
    end
  end
  
  nil
end
    
    nil # Return nil if no device found
  end

def authenticate_user!
  device = current_device
  
  if device
    # Only allow dashboard access if we have a fully authenticated session
    if cookies[:device_token].present? && session[:user_id].present? && current_user
      return # Allow through to the action
    else
      # Device exists but not authenticated - show GUID flow
      store_location
      redirect_to login_path
    end
  else
    # No device found - show new device flow
    store_location
    redirect_to login_path
  end
end

  private

  def store_location
    session[:return_to] = request.original_url if request.get?
  end

  def read_device_info(db_path)
    db = SQLite3::Database.new(Rails.root.join(db_path).to_s)
    db.results_as_hash = true
    info = db.execute("SELECT * FROM device_info")
            .each_with_object({}) { |row, hash| hash[row['key']] = row['value'] }
    db.close
    info
  rescue SQLite3::Exception => e
    Rails.logger.error "Database read error: #{e.message}"
    {}
  end
