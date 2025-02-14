class TwilioService
  COUNTRY_CODES = {
    'UK' => '44',
    'SG' => '65'
  }

  class << self
    def send_verification_code(phone_or_handle, code = nil)
      Rails.logger.info "==== TWILIO SERVICE: SENDING VERIFICATION CODE ===="
      Rails.logger.info "Input phone/handle: #{phone_or_handle}"
      
      begin
        phones = if phone_or_handle.start_with?('@')
          Rails.logger.info "Looking up user by handle: #{phone_or_handle}"
          user = User.find_by("LOWER(handle) = ?", phone_or_handle.downcase)
          user ? [user.phone] + (user.additional_phones || []) : []
        else
          [phone_or_handle]
        end

        Rails.logger.info "Phone numbers to try: #{phones.inspect}"

        if phones.empty?
          Rails.logger.error "No valid phone numbers found"
          return false
        end

        phone = select_best_phone(phones)
        Rails.logger.info "Selected phone: #{phone}"
        
        normalized_phone = normalize_phone(phone)
        Rails.logger.info "Normalized phone: #{normalized_phone}"
        
        unless normalized_phone
          Rails.logger.error "Failed to normalize phone number"
          return false
        end

        verification_code = code || rand(100000..999999).to_s
        Rails.logger.info "Generated code: #{verification_code}"
        
        begin
          Rails.logger.info "Initializing Twilio client"
          client = Twilio::REST::Client.new(
            ENV['TWILIO_ACCOUNT_SID'],
            ENV['TWILIO_AUTH_TOKEN']
          )
          
          message = client.messages.create(
            body: sms_message_for(phone_or_handle, verification_code),
            to: normalized_phone,
            from: ENV['TWILIO_PHONE_NUMBER']
          )
          
          Rails.logger.info "Successfully sent SMS!"
          Rails.logger.info "Message SID: #{message.sid}"
          Rails.logger.info "Status: #{message.status}"

          # Store the code only after successful SMS send
          store_code(normalized_phone, verification_code)
          Rails.logger.info "Stored verification code for later validation"
          
          true
        rescue Twilio::REST::RestError => e
          Rails.logger.error "Twilio REST error!"
          Rails.logger.error "Error code: #{e.code}"
          Rails.logger.error "Error message: #{e.message}"
          Rails.logger.error "More info: #{e.more_info}"
          false
        end
      rescue => e
        Rails.logger.error "==== TWILIO SERVICE ERROR ===="
        Rails.logger.error e.message
        Rails.logger.error e.backtrace.join("\n")
        false
      end
    end

    def verify_code(phone_or_handle, code)
      Rails.logger.info "Verifying code for: #{phone_or_handle}"
      
      if phone_or_handle.start_with?('@')
        user = User.find_by("LOWER(handle) = ?", phone_or_handle.downcase.gsub(/^@/, ''))
        unless user
          Rails.logger.error "User not found for handle: #{phone_or_handle}"
          return false
        end
        
        phones = [user.phone] + (user.additional_phones || [])
        # Try verification against all user's phones
        phones.any? { |phone| verify_single_phone(phone, code) }
      else
        verify_single_phone(phone_or_handle, code)
      end
    end

    def valid_phone_format?(phone)
      return false if phone.blank?
      
      cleaned = phone.to_s.gsub(/[^\d+]/, '')
      
      patterns = {
        'UK' => /^\+?44\d{10}$|^0?\d{10}$/,  # +447123456789 or 07123456789
        'SG' => /^\+?65\d{8}$/               # +6512345678
      }

      result = COUNTRY_CODES.values.any? do |code|
        patterns[COUNTRY_CODES.key(code)]&.match?(cleaned)
      end
      
      Rails.logger.info "Phone format validation for #{phone}: #{result}"
      result
    end

    private

    def sms_message_for(phone_or_handle, code)
      if phone_or_handle.start_with?('@')
        "#{code} is your SuperApp verification code for login. Don't share this code with anyone."
      else
        "#{code} is your SuperApp verification code. Welcome to SuperApp!"
      end
    end

    def verify_single_phone(phone, code)
      normalized_phone = normalize_phone(phone)
      unless normalized_phone
        Rails.logger.error "Failed to normalize phone for verification: #{phone}"
        return false
      end

      stored_code = retrieve_code(normalized_phone)
      
      Rails.logger.info "Verifying code for #{normalized_phone}"
      Rails.logger.info "Stored code: #{stored_code}, Received code: #{code}"
      
      if stored_code.present? && stored_code == code.to_s.upcase
        remove_code(normalized_phone)
        true
      else
        false
      end
    end

    def store_code(phone, code)
      key = "verification_code:#{phone}"
      Rails.cache.write(key, code, expires_in: 10.minutes)
    end

    def retrieve_code(phone)
      key = "verification_code:#{phone}"
      Rails.cache.read(key)
    end

    def remove_code(phone)
      key = "verification_code:#{phone}"
      Rails.cache.delete(key)
    end

    def normalize_phone(phone)
      return nil if phone.blank?
      
      cleaned = phone.gsub(/[^\d+]/, '')
      
      # UK number normalization
      if cleaned.match?(/^\+?44\d{10}$/) || cleaned.match?(/^0?\d{10}$/)
        if cleaned.start_with?('0')
          "+44#{cleaned[1..-1]}"
        elsif cleaned.start_with?('44')
          "+#{cleaned}"
        elsif cleaned.start_with?('+')
          cleaned
        else
          "+44#{cleaned}"
        end
      # Singapore number normalization
      elsif cleaned.match?(/^\+?65\d{8}$/)
        if cleaned.start_with?('65')
          "+#{cleaned}"
        elsif cleaned.start_with?('+')
          cleaned
        else
          "+65#{cleaned}"
        end
      else
        Rails.logger.error "Invalid phone number format: #{phone}"
        nil
      end
    end

    def select_best_phone(phones)
      # Get user's likely country from their IP or explicit selection
      user_country = detect_user_country
      
      # Try to find a phone number matching user's current country
      matching_phone = phones.find do |phone|
        normalized = normalize_phone(phone)
        next unless normalized
        
        COUNTRY_CODES.values.find do |code|
          normalized.start_with?("+#{code}") && COUNTRY_CODES.key(code) == user_country
        end
      end
      
      matching_phone || phones.first
    end

    def detect_user_country
      # This could be enhanced to use GeoIP or user preferences
      # For now defaulting to UK
      'UK'
    end
  end
end
