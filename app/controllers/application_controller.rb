class ApplicationController < ActionController::Base
include DeviceAuthenticationConcern
  include AuthenticationConcern

  before_action :authenticate_user!
  before_action :set_csrf_token
  before_action :check_ssl
  
def current_device
  return @current_device if defined?(@current_device)
  
  # First try session
  if session[:device_id]
    device = Device.find_by(id: session[:device_id])
    if device&.active?
      @current_device = device
      return @current_device
    end
  end
  
  # Then try device token
  if cookies[:device_token]
    device = Device.find_by(device_id: cookies[:device_token])
    if device&.active?
      session[:device_id] = device.id
      @current_device = device
      return @current_device
    end
  end
  
  # Finally try database path
  if cookies[:device_database_path].present?
    db_path = cookies[:device_database_path]
    if File.exist?(Rails.root.join(db_path))
      begin
        db = SQLite3::Database.new(Rails.root.join(db_path).to_s)
        db.results_as_hash = true
        device_info = db.execute("SELECT * FROM device_info")
                     .each_with_object({}) { |row, hash| hash[row['key'] || row[0]] = row['value'] || row[1] }
        db.close

        if device_info['device_id'] && device_info['verified'] == 'true'
          device = Device.find_by(device_id: device_info['device_id'])
          if device&.active?
            @current_device = device
            session[:device_id] = device.id
            session[:user_id] = device.user.id if device.user
          end
        end
      rescue SQLite3::Exception => e
        Rails.logger.error "Database read error in current_device: #{e.message}"
      end
    end
  end
  
  @current_device
end

  helper_method :current_user

  def current_device
    return @current_device if defined?(@current_device)
    current_user  # This will set @current_device as a side effect
    @current_device
  end
  helper_method :current_device

def device_verified?
  return false unless current_device&.device_database&.path
  return false unless cookies[:device_token].present? && session[:user_id].present?
  
  db_path = Rails.root.join(current_device.device_database.path)
  return false unless File.exist?(db_path)

  begin
    db = SQLite3::Database.new(db_path.to_s)
    db.results_as_hash = true
    result = db.get_first_row("SELECT value FROM device_info WHERE key = 'verified' LIMIT 1")
    db.close
    
    # Device is only verified if database flag is true AND auth cookies exist
    is_verified = result && result['value'] == 'true'
    has_auth = cookies[:device_token].present? && session[:user_id].present?
    
    is_verified && has_auth
  rescue SQLite3::Exception => e
    Rails.logger.error "Database verification check error: #{e.message}"
    false
  end
end

 helper_method :device_verified?

  private

  def authenticate_user!
    unless current_user
      redirect_to login_path, alert: 'Please login to continue'
    end
  end

  def set_csrf_token
    cookies['CSRF-TOKEN'] = {
      value: form_authenticity_token,
      domain: '.superappproject.com',
      secure: true,
      same_site: :lax
    }
  end

  def check_ssl
    unless request.ssl? || Rails.env.development?
      redirect_to "https://#{request.host}#{request.fullpath}", status: :moved_permanently
    end
  end
end
