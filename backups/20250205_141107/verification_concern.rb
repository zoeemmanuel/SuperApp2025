module VerificationConcern
  extend ActiveSupport::Concern

  private

  def handle_phone_verification(phone, device_data)
    Rails.logger.info "=== HANDLE PHONE VERIFICATION START ==="
    Rails.logger.info "Phone: #{phone}"
    
    fingerprint = DeviceRecognitionService.generate_fingerprint(device_data)
    cache_key = "phone_verification:#{fingerprint}"
    
    Rails.logger.info "Generated Fingerprint: #{fingerprint}"
    Rails.logger.info "Cache Key: #{cache_key}"
    
    # Generate code first
    verification_code = rand(100000..999999).to_s
    
    verification_data = {
      phone: phone,
      fingerprint: fingerprint,
      device_data: device_data,
      code: verification_code,
      expires_at: 10.minutes.from_now
    }

    Rails.logger.info "Setting verification data: #{verification_data.inspect}"
    
    # Use both file-based storage and cache
    store_verification_data(cache_key, verification_data)
    
    # Send the code we generated
    result = TwilioService.send_verification_code(phone, verification_code)
    Rails.logger.info "Verification code sent: #{result}"
    result
  end

  def verify_and_process_code(code, fingerprint, verification_type = :phone)
    Rails.logger.info "=== VERIFY AND PROCESS CODE ==="
    Rails.logger.info "Code: #{code}"
    Rails.logger.info "Fingerprint: #{fingerprint}"
    Rails.logger.info "Type: #{verification_type}"
    
    cache_key = "phone_verification:#{fingerprint}"
    Rails.logger.info "Looking up cache key: #{cache_key}"
    
    @verification_data = retrieve_verification_data(cache_key)
    Rails.logger.info "Verification Data from storage: #{@verification_data.inspect}"
    
    return false unless @verification_data
    return false if @verification_data[:expires_at] < Time.current
    
    if verification_type == :phone
      phone = @verification_data[:phone]
      stored_code = @verification_data[:code]
      
      Rails.logger.info "Comparing codes - Stored: #{stored_code}, Received: #{code}"
      
      if code == stored_code
        user = User.find_by(phone: phone)
        if user
          process_verified_user(user, @verification_data)
        else
          # For new users, indicate handle setup needed
          temp_key = "pending_registration:#{fingerprint}"
          store_verification_data(temp_key, @verification_data)
          remove_verification_data(cache_key)
          return { status: 'needs_handle', verification_data: @verification_data }
        end
      else
        Rails.logger.info "Code mismatch!"
        return false
      end
    else
      raise "Invalid verification type" unless @verification_data[:code] == code
      user = User.find(@verification_data[:user_id])
      process_verified_user(user, @verification_data)
    end

    remove_verification_data(cache_key)
    true
  end

  def process_verified_user(user, verification_data)
    Rails.logger.info "=== PROCESS VERIFIED USER ==="
    Rails.logger.info "User: #{user.inspect}"
    Rails.logger.info "Verification Data: #{verification_data.inspect}"
    
    ActiveRecord::Base.transaction do
      unless user.persisted?
        raise "User must be persisted before device registration"
      end
      
      device = DeviceService.register_device(
        user,
        verification_data[:device_data]
      )
      
      Rails.logger.info "Registered Device: #{device.inspect}"
      set_device_token(device)
      user
    end
  end

  def set_device_token(device)
    cookies.permanent[:device_token] = {
      value: device.device_id,
      httponly: true,
      secure: Rails.env.production?
    }
  end

  private

  def store_verification_data(key, data)
    # Use both Rails cache and file storage for redundancy
    Rails.cache.write(key, data, expires_in: 10.minutes)
    
    # Also store in file system
    storage_path = Rails.root.join('tmp', 'verification_data')
    FileUtils.mkdir_p(storage_path)
    
    File.write(
      storage_path.join("#{key}.json"),
      data.to_json
    )
    
    Rails.logger.info "Stored verification data in both cache and file"
  end

  def retrieve_verification_data(key)
    # Try cache first
    data = Rails.cache.read(key)
    return data if data.present?
    
    # Fall back to file system if cache fails
    storage_path = Rails.root.join('tmp', 'verification_data')
    file_path = storage_path.join("#{key}.json")
    
    if File.exist?(file_path)
      if File.mtime(file_path) < 10.minutes.ago
        remove_verification_data(key)
        return nil
      end
      
      data = JSON.parse(File.read(file_path)).symbolize_keys
      
      # Restore to cache
      Rails.cache.write(key, data, expires_in: 10.minutes)
      
      data
    else
      nil
    end
  end

  def remove_verification_data(key)
    Rails.cache.delete(key)
    
    file_path = Rails.root.join('tmp', 'verification_data', "#{key}.json")
    File.delete(file_path) if File.exist?(file_path)
  end
end
