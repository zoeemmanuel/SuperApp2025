module Api
  module V1
    class AuthController < Api::V1::BaseController
      include DeviceAuthenticationConcern
      include VerificationConcern
      include DeviceRecognitionConcern

      skip_before_action :verify_authenticity_token
      skip_before_action :authenticate_user!

def check_device
  Rails.logger.info "=== CHECK DEVICE START ==="
  begin
    device_data = process_device_data
    db_path = device_data.dig('database', 'path') || cookies[:device_database_path]

    if db_path && File.exist?(Rails.root.join(db_path))
      device_info = read_device_info_from_db(db_path)
      
      if device_info && device_info['device_id']
        device = Device.find_by(device_id: device_info['device_id']) ||
                Device.find_by(system_id: device_info['system_id'])
        
        if device&.user
          # Auto-login if device is verified
          if device_database_verified?(db_path)
            set_storage_headers(db_path, device_info)
            set_device_cookies(db_path)
            
            return render json: {
              status: 'device_known',
              handle: device.user.handle,
              database_path: db_path,
              masked_phone: device.user.masked_phone,
              verified: true,
              redirect_to: '/dashboard'
            }
          else
            # Device known but needs verification
            return render json: {
              status: 'device_known',
              handle: device.user.handle,
              database_path: db_path,
              masked_phone: device.user.masked_phone,
              verified: false
            }
          end
        end
      end
    end

    # No existing device, create new one
device_data = process_device_data
new_device_data = create_new_device_data(device_data['browser_info'])
sync_new_device_data(new_device_data)

    render json: { 
      status: 'unknown_device',
      database_path: new_device_data[:database_path]
    }
  rescue => e
    Rails.logger.error "Check device error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render json: { status: 'error', message: 'Failed to check device' }
  end
end

def phone_login
  Rails.logger.info "=== PHONE LOGIN START ==="
  begin
    phone = params[:phone].to_s.strip
    handle = params[:handle].to_s.strip
    device_data = process_device_data || {}
    
    Rails.logger.info "Phone: #{phone}"
    Rails.logger.info "Handle: #{handle}"
    Rails.logger.info "Database Path: #{device_data.dig('database', 'path')}"
    Rails.logger.info "Cookies: #{cookies.to_h}"
    
    # Check for existing user first
    existing_user = if handle.present?
      User.find_by(handle: handle)
    else
      User.find_by(phone: phone)
    end

    if existing_user
      Rails.logger.info "Found existing user: #{existing_user.handle}"
      
      # Check for existing verified device
      device = find_active_device_for_user(existing_user)
      if device && device_database_verified?(device.device_database&.path)
        Rails.logger.info "Found verified device: #{device.id}"
        ensure_database_exists(device)
        sync_database_path(device)
        
        session[:user_id] = existing_user.id
        set_device_token(device)
        
        return render json: {
          status: 'authenticated',
          redirect_to: '/dashboard',
          database_path: device.device_database.path
        }
      end

      # Known user but needs verification
      Rails.logger.info "User known but needs verification"

      # Generate and send verification code
      verification_id = SecureRandom.uuid
      verification_code = rand(100000..999999).to_s      

      verification_data = {
        phone: existing_user.phone,
        verification_id: verification_id,
        device_data: device_data,
        code: verification_code,
        expires_at: 10.minutes.from_now,
        type: 'phone'
      }

      Rails.logger.info "Setting verification data: #{verification_data.inspect}"
      store_verification_data("verification:#{verification_id}", verification_data)

      # Set verification cookies
      cookie_opts = {
        value: verification_id,
        domain: request.domain || request.host,
        secure: true,
        same_site: :lax,
        path: '/',
        expires: 10.minutes.from_now,
        httponly: true
      }

      cookies[:verification_id] = cookie_opts
      cookies.signed[:verification_id] = cookie_opts

      if TwilioService.send_verification_code(existing_user.phone, verification_code)
        return render json: {
          status: 'device_known',
          handle: existing_user.handle,
          database_path: nil,
          masked_phone: existing_user.masked_phone,
          verified: false,
          message: "Welcome back #{existing_user.handle}!"
        }
      else
        return render json: { 
          status: 'error', 
          message: 'Failed to send verification code' 
        }, status: :unprocessable_entity
      end
    end

    # Phone number validation
    unless TwilioService.valid_phone_format?(phone)
      Rails.logger.info "Invalid phone format: #{phone}"
      return render json: { 
        status: 'error',
        message: 'Please enter a valid UK (+44) or Singapore (+65) phone number'
      }, status: :unprocessable_entity
    end

    # Handle device database path from cookies
    if cookies[:device_database_path] && !device_data.dig('database', 'path')
      Rails.logger.info "Using database path from cookies: #{cookies[:device_database_path]}"
      device_data['database'] = {
        'path' => cookies[:device_database_path],
        'exists' => true
      }
    end

    # New verification flow for unknown user/device
    verification_id = SecureRandom.uuid
    verification_code = rand(100000..999999).to_s

    verification_data = {
      phone: phone,
      verification_id: verification_id,
      device_data: device_data,
      code: verification_code,
      expires_at: 10.minutes.from_now,
      type: 'phone'
    }

    Rails.logger.info "Setting verification data: #{verification_data.inspect}"
    store_verification_data("verification:#{verification_id}", verification_data)

    # Set verification cookies
    cookie_opts = {
      value: verification_id,
      domain: request.domain || request.host,
      secure: true,
      same_site: :lax,
      path: '/',
      expires: 10.minutes.from_now,
      httponly: true
    }

    cookies[:verification_id] = cookie_opts
    cookies.signed[:verification_id] = cookie_opts

    # Send verification code
    if TwilioService.send_verification_code(phone, verification_code)
      Rails.logger.info "Verification code sent to #{phone}"
      
      @storage_header = {
        device_database_path: device_data.dig('database', 'path'),
        verification_id: verification_id,
        sync_time: Time.current.iso8601
      }.to_json
      
      response.headers['X-Set-Storage'] = @storage_header

      render json: {
        status: 'pending_verification',
        message: "Enter the verification code sent to #{User.mask_phone(phone)}",
        database_path: device_data.dig('database', 'path')
      }
    else
      Rails.logger.error "Failed to send verification code to #{phone}"
      render json: {
        status: 'error',
        message: 'Failed to send verification code'
      }, status: :unprocessable_entity
    end
  rescue => e
    Rails.logger.error "Phone login error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render json: {
      status: 'error',
      message: 'Failed to process phone login'
    }, status: :internal_server_error
  end
end

def verify_code
        Rails.logger.info "=== VERIFY CODE START ==="
        Rails.logger.info "Database Path Cookie: #{cookies[:device_database_path]}"
        Rails.logger.info "Verification ID Cookie: #{cookies.signed[:verification_id]}"
        
        begin
          code = params[:code].to_s.strip
          verification_id = cookies.signed[:verification_id]
          device_data = process_device_data || {}
          
          Rails.logger.info "Processing verification code: #{code}"
          Rails.logger.info "With verification ID: #{verification_id}"
          
          # Verify session exists
          unless verification_id
            Rails.logger.error "No verification ID found in signed cookies"
            return render json: { 
              status: 'error',
              message: 'Verification session expired'
            }, status: :unprocessable_entity
          end

          # Retrieve verification data
          verification_data = retrieve_verification_data("verification:#{verification_id}")
          unless verification_data
            Rails.logger.error "No verification data found for ID: #{verification_id}"
            return render json: {
              status: 'error',
              message: 'Verification session expired'
            }, status: :unprocessable_entity
          end

          # Verify code matches
          unless verification_data[:code] == code
            Rails.logger.error "Code mismatch: expected #{verification_data[:code]}, got #{code}"
            return render json: {
              status: 'error',
              message: 'Invalid verification code'
            }, status: :unprocessable_entity
          end

          # Check expiration
          expires_at = verification_data[:expires_at].is_a?(String) ? 
            Time.parse(verification_data[:expires_at]) : verification_data[:expires_at]
          
          if expires_at < Time.current
            remove_verification_data("verification:#{verification_id}")
            clear_verification_cookies
            return render json: {
              status: 'error',
              message: 'Verification code expired'
            }, status: :unprocessable_entity
          end

          # Process verification for existing user
          user = User.find_by(phone: verification_data[:phone])
          if user
            device = find_or_create_device(user, device_data)
            ensure_database_exists(device)
            mark_device_verified(device)
            sync_database_path(device)
            
            session[:user_id] = user.id
            set_device_token(device)

            remove_verification_data("verification:#{verification_id}")
            clear_verification_cookies

            render json: {
              status: 'authenticated',
              redirect_to: '/dashboard',
              database_path: device.device_database.path,
              handle: user.handle
            }
          else
            # New user needs to set handle
            verification_data[:verified] = true
            store_verification_data("handle_pending:#{verification_id}", verification_data)
            
            @storage_header = {
              device_database_path: device_data.dig('database', 'path'),
              sync_time: Time.current.iso8601
            }.to_json
            
            response.headers['X-Set-Storage'] = @storage_header

            render json: {
              status: 'needs_handle',
              message: 'Please set your handle to continue',
              database_path: device_data.dig('database', 'path')
            }
          end
        rescue => e
          Rails.logger.error "Code verification error: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          render json: {
            status: 'error',
            message: 'Verification failed'
          }, status: :internal_server_error
        end
      end

      def verify_guid
        Rails.logger.info "=== VERIFY GUID START ==="
        
        begin
          handle = params[:handle].to_s.strip
          device_data = process_device_data || {}
          
          Rails.logger.info "Handle: #{handle}"
          Rails.logger.info "Device Data: #{device_data.inspect}"

          # Validate handle format
          unless handle.match?(/^@[a-zA-Z0-9_]+$/)
            return render json: {
              status: 'error',
              message: 'Invalid handle format'
            }, status: :unprocessable_entity
          end

          # Find user by handle
          user = User.find_by(handle: handle)
          unless user
            return render json: {
              status: 'error',
              message: 'Handle not found'
            }, status: :unprocessable_entity
          end

          # Check if device is already verified
          device = find_active_device_for_user(user)
          if device && device_database_verified?(device.device_database&.path)
            ensure_database_exists(device)
            sync_database_path(device)
            
            session[:user_id] = user.id
            set_device_token(device)
            
            render json: {
              status: 'authenticated',
              redirect_to: '/dashboard',
              database_path: device.device_database.path
            }
          else
            # Start verification process
            verification_id = SecureRandom.uuid
            verification_code = rand(100000..999999).to_s

            verification_data = {
              handle: handle,
              verification_id: verification_id,
              device_data: device_data,
              code: verification_code,
              expires_at: 10.minutes.from_now,
              type: 'guid'
            }

            store_verification_data("verification:#{verification_id}", verification_data)
            set_verification_cookies(verification_id)

            if TwilioService.send_verification_code(user.phone, verification_code)
              @storage_header = {
                device_database_path: device_data.dig('database', 'path'),
                verification_id: verification_id,
                sync_time: Time.current.iso8601
              }.to_json
              
              response.headers['X-Set-Storage'] = @storage_header

              render json: {
                status: 'pending_verification',
                message: "Enter the verification code sent to #{User.mask_phone(user.phone)}",
                database_path: device_data.dig('database', 'path')
              }
            else
              render json: {
                status: 'error',
                message: 'Failed to send verification code'
              }, status: :unprocessable_entity
            end
          end
        rescue => e
          Rails.logger.error "GUID verification error: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          render json: {
            status: 'error',
            message: 'Failed to verify handle'
          }, status: :internal_server_error
        end
      end
def update_handle
  Rails.logger.info "=== UPDATE HANDLE START ==="
  begin
    # Clean and format the handle
    handle = params[:handle].to_s.strip
    handle = "@#{handle}" unless handle.start_with?('@')

    Rails.logger.info "Processing handle: #{handle}"
    
    verification_id = cookies.signed[:verification_id]
    
    # Validate handle format
    unless handle.match?(/^@[a-zA-Z0-9_]+$/)
      return render json: {
        status: 'error',
        message: 'Handle must start with @ and contain only letters, numbers, and underscores'
      }, status: :unprocessable_entity
    end

    # Check handle availability
    if User.exists?(handle: handle)
      return render json: {
        status: 'error',
        message: 'This handle is already taken'
      }, status: :unprocessable_entity
    end

    verification_data = retrieve_verification_data("handle_pending:#{verification_id}")
    unless verification_data
      return render json: {
        status: 'error',
        message: 'Verification session expired'
      }, status: :unprocessable_entity
    end

    # Create user and device
    user = User.create!(
      phone: verification_data[:phone],
      handle: handle
    )

    device = find_or_create_device(user, verification_data[:device_data] || {})
    ensure_database_exists(device)
    mark_device_verified(device)
    sync_database_path(device)
    
    session[:user_id] = user.id
    set_device_token(device)

    remove_verification_data("handle_pending:#{verification_id}")
    clear_verification_cookies

render json: {
  status: 'authenticated',
  redirect_to: '/dashboard',
  database_path: device.device_database.path,
  html: '<html><body><script>window.location.href="/dashboard";</script></body></html>'
}
  rescue => e
    Rails.logger.error "Handle update error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render json: {
      status: 'error',
      message: 'Failed to update handle'
    }, status: :internal_server_error
  end
end

private

      def read_device_info_from_db(db_path)
        return nil unless db_path && File.exist?(Rails.root.join(db_path))
        
        begin
          db = SQLite3::Database.new(Rails.root.join(db_path).to_s)
          db.results_as_hash = true
          device_info = db.execute("SELECT * FROM device_info")
                         .each_with_object({}) { |row, hash| hash[row['key'] || row[0]] = row['value'] || row[1] }
          db.close
          
          Rails.logger.info "Found device info in SQLite: #{device_info.inspect}"
          device_info
        rescue SQLite3::Exception => e
          Rails.logger.error "Database read error: #{e.message}"
          nil
        end
      end

      def device_database_verified?(db_path)
        return false unless db_path && File.exist?(Rails.root.join(db_path))
        
        begin
          db = SQLite3::Database.new(Rails.root.join(db_path).to_s)
          db.results_as_hash = true
          result = db.get_first_row("SELECT value FROM device_info WHERE key = 'verified' LIMIT 1")
          db.close
          
          result && result['value'] == 'true'
        rescue SQLite3::Exception => e
          Rails.logger.error "Database verification check error: #{e.message}"
          false
        end
      end

      def find_or_create_device(user, device_data)
        device = if device_data.dig('database', 'path')
          device_info = read_device_info_from_db(device_data['database']['path'])
          if device_info && device_info['device_id']
            Device.find_by(device_id: device_info['device_id']) ||
            Device.find_by(system_id: device_info['system_id'])
          end
        end

        unless device
          device = Device.create!(
            user: user,
            device_id: SecureRandom.uuid,
            system_id: SecureRandom.uuid,
            device_type: detect_device_type(device_data),
            device_info: {
              created_at: Time.current.iso8601,
              browser_info: device_data['browser_info']
            }
          )
        end

        device.update!(user: user) if device.user_id != user.id
        device
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

      def sync_database_path(device)
        return unless device.device_database&.path

        cookies[:device_database_path] = {
          value: device.device_database.path,
          domain: request.domain || request.host,
          secure: true,
          same_site: :lax,
          path: '/',
          expires: 1.year.from_now,
          httponly: false
        }

        @storage_header = {
          device_database_path: device.device_database.path,
          sync_time: Time.current.iso8601
        }.to_json

        response.headers['X-Set-Storage'] = @storage_header
      end

def find_or_create_device(user, device_data)
  device = if device_data['database'].present?
    DeviceService.find_device_by_database(device_data)
  end

  device ||= DeviceService.register_device(user, device_data)
  device.update!(user: user) if device.user_id != user.id
  device
end

      def ensure_database_exists(device)
        return unless device.device_database&.path
        db_path = Rails.root.join(device.device_database.path)
        unless File.exist?(db_path)
          Rails.logger.info "Creating new device database at #{db_path}"
          FileUtils.mkdir_p(File.dirname(db_path))
          
          db = SQLite3::Database.new(db_path.to_s)
          setup_database_tables(db)
          insert_initial_data(db, device.device_id, device.system_id, nil)
          db.close
        end
      end

def mark_device_verified(device)
  return unless device&.device_database&.path
  
  begin
    db_path = Rails.root.join(device.device_database.path)
    db = SQLite3::Database.new(db_path.to_s)
    
    # Update the verified status in the device database
    db.execute(
      "INSERT OR REPLACE INTO device_info (key, value) VALUES (?, ?)", 
      ["verified", "true"]
    )
    
    # Update last verification time
    db.execute(
      "INSERT OR REPLACE INTO device_info (key, value) VALUES (?, ?)",
      ["last_verified_at", Time.current.iso8601]
    )
    
    db.close
    
    # Update device record
    device.update!(
      active: true,
      last_active_at: Time.current
    )
    
    Rails.logger.info "Device #{device.id} marked as verified"
  rescue SQLite3::Exception => e
    Rails.logger.error "Failed to mark device as verified: #{e.message}"
    raise
  end
end

      def set_device_token(device)
        return unless device&.device_database&.path
        
        token = SecureRandom.uuid
        db_path = Rails.root.join(device.device_database.path)
        
        begin
          db = SQLite3::Database.new(db_path.to_s)
          db.execute("INSERT INTO device_info (key, value) VALUES (?, ?)", 
                    ["device_token", token])
          db.close

          cookies[:device_token] = {
            value: token,
            domain: request.domain || request.host,
            secure: true,
            same_site: :lax,
            path: '/',
            expires: 1.year.from_now,
            httponly: true
          }
        rescue SQLite3::Exception => e
          Rails.logger.error "Error setting device token: #{e.message}"
        end
      end
    end
  end
end

