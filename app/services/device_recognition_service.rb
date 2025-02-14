class DeviceRecognitionService
  class << self
    def recognize_or_register(handle, device_data, request)
      Rails.logger.info "=== RECOGNIZE OR REGISTER START ==="
      Rails.logger.info "Handle: #{handle}"
      Rails.logger.info "Device Data: #{device_data.inspect}"
      Rails.logger.info "Host: #{request.host}"
      Rails.logger.info "All Cookies: #{request.cookies.inspect}"
      
      # Only check domain-level database path cookie
      database_path = request.cookies['device_database_path']
      
      if database_path.present?
        Rails.logger.info "Found database path in cookie: #{database_path}"
        if device = find_device_by_database_path(database_path)
          Rails.logger.info "Found device by cookie path: #{device.id}"
          return {
            status: 'known',
            device: device,
            handle: device.user&.handle,
            masked_phone: mask_phone_number(device.user&.phone)
          }
        end
      end
      
      # Then try database path from device data
      if device_data.dig('database', 'path').present?
        Rails.logger.info "Checking device data path: #{device_data['database']['path']}"
        if device = find_device_by_database_path(device_data['database']['path'])
          Rails.logger.info "Found device by data path: #{device.id}"
          return {
            status: 'known',
            device: device,
            handle: device.user&.handle,
            masked_phone: mask_phone_number(device.user&.phone)
          }
        end
      end

      Rails.logger.info "No existing device found, needs verification"
      { status: 'needs_verification' }
    end

    def parse_user_agent(user_agent)
      return {} unless user_agent.present?

      ua = user_agent.downcase
      browser_info = {
        browser: detect_browser(ua),
        version: detect_browser_version(ua),
        os: detect_os(ua)
      }

      Rails.logger.info "Parsed user agent: #{browser_info.inspect}"
      browser_info
    end

    private

    def find_device_by_database_path(path)
      return nil unless path.present?
      
      begin
        decoded_path = URI.decode_www_form_component(path)
        Rails.logger.info "Looking up device with decoded path: #{decoded_path}"
        
        device = DeviceService.find_device_by_database({
          'database' => { 'path' => decoded_path }
        })
        
        if device
          Rails.logger.info "Found device: #{device.id}"
          if verify_device(device)
            Rails.logger.info "Device verified successfully"
            return device
          else
            Rails.logger.info "Device verification failed"
            return nil
          end
        end
        
        Rails.logger.info "No device found for path"
        nil
      rescue => e
        Rails.logger.error "Error finding device by path: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        nil
      end
    end

    def verify_device(device)
      return false unless device&.device_database&.full_path
      return false unless File.exist?(device.device_database.full_path)
      return false unless device.active?
      true
    end

    def detect_browser(ua)
      if ua.include?('firefox')
        'Firefox'
      elsif ua.include?('edg/')
        'Edge'
      elsif ua.include?('chrome') && !ua.include?('edg/')
        'Chrome'
      elsif ua.include?('safari') && !ua.include?('chrome')
        'Safari'
      else
        'Unknown'
      end
    end

    def detect_browser_version(ua)
      version = case detect_browser(ua)
      when 'Firefox'
        ua.match(/firefox\/([\d.]+)/)&.captures&.first
      when 'Chrome'
        ua.match(/chrome\/([\d.]+)/)&.captures&.first
      when 'Safari'
        ua.match(/version\/([\d.]+)/)&.captures&.first
      when 'Edge'
        ua.match(/edg\/([\d.]+)/)&.captures&.first
      end
      
      version || '0.0'
    end

    def detect_os(ua)
      if ua.include?('windows')
        'Windows'
      elsif ua.include?('mac os') || ua.include?('macos')
        'macOS'
      elsif ua.include?('linux')
        'Linux'
      elsif ua.include?('ios') || ua.include?('iphone') || ua.include?('ipad')
        'iOS'
      elsif ua.include?('android')
        'Android'
      else
        'Unknown'
      end
    end

    def mask_phone_number(phone)
      return nil unless phone.present?
      "*******#{phone.last(4)}"
    end
  end
end
