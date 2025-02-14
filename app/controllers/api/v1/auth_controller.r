module Api
  module V1
    class AuthController < ApplicationController
      def check_device
        Rails.logger.info "=== CHECK DEVICE START ==="
        begin
          device_data = process_device_data
          
          if device_data.dig('database', 'path')
            device = Device.find_by_database_path(device_data['database']['path'])
            
            if device&.user
              # Check if device is fully verified
              if device.verified && File.exist?(Rails.root.join(device.device_database.path))
                sync_database_path(device)
                return render json: {
                  status: 'device_known',
                  handle: device.user.handle,
                  database_path: device.device_database.path,
                  masked_phone: device.user.masked_phone,
                  verified: true,
                  redirect_to: '/dashboard'
                }
              else
                # Device known but needs verification
                return render json: {
                  status: 'device_known',
                  handle: device.user.handle,
                  database_path: device.device_database.path,
                  masked_phone: device.user.masked_phone,
                  verified: false
                }
              end
            end
          end
          
          render json: { status: 'unknown_device' }
        rescue => e
          Rails.logger.error "Device check error: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          render json: { status: 'error', message: 'Device check failed' }, status: :internal_server_error
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
          
          # Handle GUID-based login
          if handle.present?
            user = User.find_by(handle: handle)
            if user
              device = find_active_device_for_user(user)
              if device && device.verified
                ensure_database_exists(device)
                sync_database_path(device)
                
                session[:user_id] = user.id
                set_device_token(device)
                
                return render json: {
                  status: 'authenticated',
                  redirect_to: '/dashboard',
                  database_path: device.device_database.path
                }
              end
            end
          end
          
          # Regular phone-based login flow
          unless TwilioService.valid_phone_format?(phone)
            return render json: {
              status: 'error',
              message: 'Please enter a valid UK (+44) or Singapore (+65) phone number'
            }, status: :unprocessable_entity
          end

          # Check for any existing devices with this phone
          existing_user = User.find_by(phone: phone)
          if existing_user
            existing_device = find_active_device_for_user(existing_user)
            if existing_device
              Rails.logger.info "Found existing device: #{existing_device.id}"
              ensure_database_exists(existing_device)
              sync_database_path(existing_device)
              
              if existing_device.verified
                session[:user_id] = existing_user.id
                set_device_token(existing_device)
                
                return render json: {
                  status: 'authenticated',
                  redirect_to: '/dashboard',
                  database_path: existing_device.device_database.path
                }
              else
                return render json: {
                  status: 'device_known',
                  handle: existing_user.handle,
                  database_path: existing_device.device_database.path,
                  masked_phone: existing_user.masked_phone,
                  verified: false
                }
              end
            end
          end
# New verification flow
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
          
          unless verification_id
            Rails.logger.error "No verification ID found in signed cookies"
            return render json: { 
              status: 'error',
              message: 'Verification session expired'
            }, status: :unprocessable_entity
          end

          verification_data = retrieve_verification_data("verification:#{verification_id}")
          unless verification_data
            Rails.logger.error "No verification data found for ID: #{verification_id}"
            return render json: {
              status: 'error',
              message: 'Verification session expired'
            }, status: :unprocessable_entity
          end

          Rails.logger.info "Retrieved verification data: #{verification_data.inspect}"
          
          unless verification_data[:code] == code
            Rails.logger.error "Code mismatch: expected #{verification_data[:code]}, got #{code}"
            return render json: {
              status: 'error',
              message: 'Invalid verification code'
            }, status: :unprocessable_entity
          end

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

          user = User.find_by(phone: verification_data[:phone])
          if user
            device = process_verified_user(user, device_data)
            ensure_database_exists(device)
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

      private

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
        
        if device_data['database'].present?
          {
            'database' => device_data['database']
          }
        else
          db_path = cookies[:device_database_path]
          
          if db_path
            {
              'database' => {
                'path' => db_path,
                'exists' => true
              }
            }
          else
            { 'database' => nil }
          end
        end
      end

      def find_active_device_for_user(user)
        Device.where(user_id: user.id).find_each do |device|
          next unless device.device_database&.path
          return device if File.exist?(Rails.root.join(device.device_database.path))
        end
        nil
      end

      def clear_verification_cookies
        cookie_opts = {
          value: nil,
          expires: 1.minute.ago,
          domain: request.domain || request.host,
          secure: true,
          same_site: :lax,
          path: '/'
        }
        
        cookies[:verification_id] = cookie_opts
        cookies.signed[:verification_id] = cookie_opts
      end

      def ensure_database_exists(device)
        return unless device.device_database&.path
        
        db_path = Rails.root.join(device.device_database.path)
        unless File.exist?(db_path)
          Rails.logger.info "Creating new device database at #{db_path}"
          FileUtils.mkdir_p(File.dirname(db_path))
          SQLite3::Database.new(db_path.to_s)
        end
      end

      def sync_database_path(device)
        return unless device.device_database&.path

        cookies[:device_database_path] = {
          value: device.device_database.path,
          domain: request.domain || request.host,
          secure: true,
          same_site: :lax,
          path: '/',
          expires: 1.year.from_now
        }

        @storage_header = {
          device_database_path: device.device_database.path,
          sync_time: Time.current.iso8601
        }.to_json

        response.headers['X-Set-Storage'] = @storage_header
      end

      def set_device_token(device)
        cookies[:device_token] = {
          value: DeviceService.generate_token(device),
          domain: request.domain || request.host,
          secure: true,
          same_site: :lax,
          path: '/',
          expires: 1.year.from_now,
          httponly: true
        }
      end
    end
  end
end
