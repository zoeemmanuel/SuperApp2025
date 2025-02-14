module VerificationConcern
  extend ActiveSupport::Concern

  private

def clear_verification_cookies
    # Normal cookie
    cookies[:verification_id] = {
      value: nil,
      expires: 1.second.ago,
      domain: determine_cookie_domain,
      path: '/',
      secure: true,
      same_site: :lax
    }

    # Signed cookie
    cookies.signed[:verification_id] = {
      value: nil,
      expires: 1.second.ago,
      domain: determine_cookie_domain,
      path: '/',
      secure: true,
      same_site: :lax
    }
  end

  def handle_phone_verification(phone, device_data)
    Rails.logger.info "=== HANDLE PHONE VERIFICATION START ==="
    Rails.logger.info "Phone: #{phone}"
    Rails.logger.info "Raw Device Data for verification: #{device_data.inspect}"
    
    verification_id = SecureRandom.uuid
    cache_key = "verification:#{verification_id}"
    
    Rails.logger.info "Generated verification_id: #{verification_id}"
    verification_code = rand(100000..999999).to_s

    verification_data = {
      phone: phone,
      verification_id: verification_id,
      device_data: device_data.presence || {},
      code: verification_code,
      expires_at: 10.minutes.from_now,
      type: 'phone'
    }

    Rails.logger.info "Setting verification data: #{verification_data.inspect}"
    store_verification_data(cache_key, verification_data)
    
    if TwilioService.send_verification_code(phone, verification_code)
      cookies.signed[:verification_id] = {
        value: verification_id,
        domain: determine_cookie_domain,
        secure: true,
        same_site: :lax,
        path: '/',
        expires: 10.minutes.from_now,
        httponly: true
      }
      
      Rails.logger.info "Verification code sent: #{verification_code}"
      
      storage_data = {
        device_database_path: device_data.dig('database', 'path'),
        verification_id: verification_id,
        sync_time: Time.current.iso8601
      }
      
      response.headers['X-Set-Storage'] = storage_data.to_json
      
      { 
        status: 'pending_verification',
        message: "Enter the verification code sent to #{User.mask_phone(phone)}",
        masked_phone: User.mask_phone(phone),
        verification_id: verification_id
      }
    else
      { 
        status: 'error',
        message: 'Failed to send verification code'
      }
    end
  end

  def verify_and_process_code(code, verification_id, device_data)
    Rails.logger.info "=== VERIFY AND PROCESS CODE ==="
    Rails.logger.info "Code: #{code}"
    Rails.logger.info "Verification ID: #{verification_id}"
    Rails.logger.info "Device Data: #{device_data.inspect}"
    
    verification_data = retrieve_verification_data("verification:#{verification_id}")
    unless verification_data
      return { status: 'error', message: 'Verification session expired' }
    end

    Rails.logger.info "Retrieved verification data: #{verification_data.inspect}"

    unless verification_data[:code] == code
      return { status: 'error', message: 'Invalid verification code' }
    end

    expires_at = verification_data[:expires_at].is_a?(String) ? 
      Time.parse(verification_data[:expires_at]) : verification_data[:expires_at]
    
    if expires_at < Time.current
      remove_verification_data("verification:#{verification_id}")
      return { status: 'error', message: 'Verification code expired' }
    end

    # Process verified user
    user = User.find_by(phone: verification_data[:phone])
    if user
      device = process_verified_user(user, device_data.presence || {})
      return {
        status: 'authenticated',
        device: device,
        database_path: device.device_database&.path,
        handle: user.handle
      }
    else
      verification_data[:verified] = true
      store_verification_data("handle_pending:#{verification_id}", verification_data)
      return { 
        status: 'needs_handle',
        verification_id: verification_id
      }
    end
  end

  def store_verification_data(key, data)
    Rails.cache.write(key, data, expires_in: 10.minutes)
    
    storage_path = Rails.root.join('tmp', 'verification_data')
    FileUtils.mkdir_p(storage_path)
    
    File.write(
      storage_path.join("#{key}.json"),
      data.to_json
    )
    
    Rails.logger.info "Stored verification data for key: #{key}"
    Rails.logger.info "Data: #{data.inspect}"
  end

  def retrieve_verification_data(key)
    data = Rails.cache.read(key)
    
    if data.present?
      Rails.logger.info "Retrieved verification data from cache for key: #{key}"
      return data
    end
    
    file_path = Rails.root.join('tmp', 'verification_data', "#{key}.json")
    if File.exist?(file_path)
      data = JSON.parse(File.read(file_path)).symbolize_keys
      Rails.cache.write(key, data, expires_in: 10.minutes)
      Rails.logger.info "Retrieved verification data from file for key: #{key}"
      data
    else
      Rails.logger.info "No verification data found for key: #{key}"
      nil
    end
  end

  def remove_verification_data(key)
    Rails.cache.delete(key)
    
    file_path = Rails.root.join('tmp', 'verification_data', "#{key}.json")
    File.delete(file_path) if File.exist?(file_path)
    
    Rails.logger.info "Removed verification data for key: #{key}"
  end

  def process_verified_user(user, device_data)
    Rails.logger.info "=== PROCESS VERIFIED USER ==="
    Rails.logger.info "User: #{user.inspect}"
    Rails.logger.info "Device Data: #{device_data.inspect}"
    
    ActiveRecord::Base.transaction do
      device = find_or_create_device(user, device_data)
      device.update!(active: true, last_active_at: Time.current)
      
      Rails.logger.info "Device processed: #{device.inspect}"
      ensure_database_exists(device)
      device
    end
  end

  def find_or_create_device(user, device_data)
    device = if device_data['database'].present?
      DeviceService.find_device_by_database(device_data)
    end
    
    device ||= DeviceService.register_device(user, device_data)
    device
  end

  def ensure_database_exists(device)
    return if device&.device_database&.path && 
             File.exist?(Rails.root.join(device.device_database.path))
    
    Rails.logger.info "Setting up missing database for device: #{device.id}"
    DeviceService.setup_device_database(device)
  end

  def find_active_device_for_user(user)
    return nil unless user
    user.devices.find_by(active: true, user: user)
  end

  def determine_cookie_domain
    return request.domain if request.domain.present?
    return request.host if request.host.present?
    'localhost'
  end
end
