class DashboardController < ApplicationController
include DeviceAuthenticationConcern
  include AuthenticationConcern

  before_action :ensure_device_verified
  before_action :authenticate_user!
  
  def index
    @user = current_user
    @current_device = current_device
    @user_data = {
      handle: @user.handle,
      phone: @user.phone,
      devices: @user.devices.map { |device|
        {
          id: device.id,
          name: get_device_name(device),
          device_type: device.device_type,
          last_active_at: device.last_active_at,
          is_current: device == @current_device,
          device_info: device.device_info
        }
      }
    }
    
    respond_to do |format|
      format.html
      format.json { render json: @user_data }
    end
  end

  private

  def ensure_device_verified
    return if session[:user_id].present?
    
    if cookies[:device_database_path].present?
      db_path = cookies[:device_database_path]
      if File.exist?(Rails.root.join(db_path))
        device_info = read_device_info(db_path)
        if device_info['verified'] == 'true'
          device = Device.find_by(device_id: device_info['device_id'])
          if device&.active? && device.user
            session[:user_id] = device.user.id
            return
          end
        end
      end
    end
    
    redirect_to login_path
  end

  def get_device_name(device)
    info = device.device_info
    return info['device_name'] if info['device_name'].present?
    return "#{info['model']}" if info['model'].present?
    return info['platform'] if info['platform'].present?
    device.device_type.capitalize
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
end
