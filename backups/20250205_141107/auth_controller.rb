module Api
  module V1
    class AuthController < Api::V1::BaseController
      include DeviceAuthenticationConcern
      include VerificationConcern

      skip_before_action :verify_authenticity_token
      skip_before_action :authenticate_user!

      def check_device
        Rails.logger.info "=== CHECK DEVICE START ==="
        Rails.logger.info "Headers: #{request.headers['HTTP_X_DEVICE_DATA']}"
        
        begin
          device_data = JSON.parse(request.headers['HTTP_X_DEVICE_DATA'] || '{}')
          fingerprint = DeviceRecognitionService.generate_fingerprint(device_data)
          
          if cookies[:device_token].present?
            device = Device.find_by(device_id: cookies[:device_token], active: true)
            if device&.fingerprint == fingerprint
              Rails.logger.info "Found matching device: #{device.id}"
              render json: {
                status: 'authenticated',
                redirect_to: '/dashboard'
              }
              return
            end
          end
          
          device = Device.find_by(fingerprint: fingerprint)
          if device&.user&.handle.present?
            Rails.logger.info "Known hardware, needs verification: #{device.id}"
            render json: {
              status: 'device_known',
              handle: device.user.handle,
              masked_phone: "...#{device.user.phone[-4..-1]}",
              device_name: device.device_info['device_name']
            }
            return
          end
          
          Rails.logger.info "Unknown device or new hardware"
          render json: { status: 'unknown_device' }
        rescue => e
          Rails.logger.error "Check device error: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          render json: {
            status: 'error',
            message: 'Failed to check device status'
          }, status: :internal_server_error
        end
      end

      def phone_login
        Rails.logger.info "=== PHONE LOGIN START ==="
        Rails.logger.info "Params: #{params.inspect}"
        
        begin
          phone = params[:phone].to_s.strip
          device_data = JSON.parse(request.headers['HTTP_X_DEVICE_DATA'] || '{}')
          
          Rails.logger.info "Phone: #{phone}"
          Rails.logger.info "Device Data: #{device_data.inspect}"
          
          unless TwilioService.valid_phone_format?(phone)
            Rails.logger.warn "Invalid phone format: #{phone}"
            return render json: { 
              status: 'error',
              message: 'Please enter a valid UK (+44) or Singapore (+65) phone number'
            }, status: :unprocessable_entity
          end

          if handle_phone_verification(phone, device_data)
            Rails.logger.info "Verification code sent to #{phone}"
            masked_phone = "...#{phone[-4..-1]}"
            render json: {
              status: 'pending_verification',
              message: "Enter the verification code sent to #{masked_phone}"
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
        Rails.logger.info "Params: #{params.inspect}"
        
        begin
          code = params[:code].to_s.strip.upcase
          device_data = JSON.parse(request.headers['HTTP_X_DEVICE_DATA'] || '{}')
          fingerprint = DeviceRecognitionService.generate_fingerprint(device_data)
          
          result = verify_and_process_code(code, fingerprint)
          
          if result.is_a?(Hash) && result[:status] == 'needs_handle'
            render json: { 
              status: 'needs_handle',
              message: 'Please set your handle to continue'
            }
          elsif result
            render json: {
              status: 'authenticated',
              redirect_to: '/dashboard'
            }
          else
            render json: { 
              status: 'error',
              message: 'Invalid verification code'
            }, status: :unprocessable_entity
          end
        rescue => e
          Rails.logger.error "Code verification error: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          render json: {
            status: 'error',
            message: e.message
          }, status: :internal_server_error
        end
      end

      def update_handle
        Rails.logger.info "=== UPDATE HANDLE START ==="
        Rails.logger.info "Params: #{params.inspect}"
        
        begin
          handle = params[:handle].to_s.strip
          device_data = JSON.parse(request.headers['HTTP_X_DEVICE_DATA'] || '{}')
          fingerprint = DeviceRecognitionService.generate_fingerprint(device_data)
          
          # Get cached verification data
          temp_key = "pending_registration:#{fingerprint}"
          verification_data = retrieve_verification_data(temp_key)
          
          Rails.logger.info "Retrieved verification data: #{verification_data.inspect}"
          
          unless verification_data
            return render json: {
              status: 'error',
              message: 'Verification session expired'
            }, status: :unprocessable_entity
          end
          
          # Add @ if not present
          handle = "@#{handle}" unless handle.start_with?('@')
          
          unless handle =~ /\A@[a-zA-Z0-9_]+\z/
            return render json: { 
              status: 'error',
              message: 'Handle must start with @ and contain only letters and numbers'
            }, status: :unprocessable_entity
          end

          User.transaction do
            user = User.new(
              phone: verification_data[:phone],
              handle: handle
            )
            
            if user.save
              device = DeviceService.register_device(user, verification_data[:device_data])
              set_device_token(device)
              
              # Clear the temporary verification data
              remove_verification_data(temp_key)
              
              render json: {
                status: 'success',
                handle: user.handle,
                redirect_to: '/dashboard'
              }
            else
              render json: {
                status: 'error',
                message: user.errors.full_messages.join(', ')
              }, status: :unprocessable_entity
            end
          end
        rescue => e
          Rails.logger.error "Handle creation error: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          render json: {
            status: 'error',
            message: 'Failed to create handle'
          }, status: :internal_server_error
        end
      end

      def verify_handle
        Rails.logger.info "=== VERIFY HANDLE START ==="
        handle = params[:handle].to_s.strip
        device_data = JSON.parse(request.headers['HTTP_X_DEVICE_DATA'] || '{}')
        
        result = DeviceRecognitionService.recognize_or_register(
          handle, 
          device_data,
          request
        )
        
        if result[:status] == 'known'
          render json: {
            status: 'success',
            redirect_to: '/dashboard'
          }
        else
          render json: result
        end
      end

      def verify_guid
        Rails.logger.info "=== VERIFY GUID START ==="
        Rails.logger.info "Params: #{params.inspect}"
        
        begin
          handle = params[:handle].to_s.strip
          device_data = JSON.parse(request.headers['HTTP_X_DEVICE_DATA'] || '{}')
          
          Rails.logger.info "Looking for handle: #{handle}"
          user = User.find_by("LOWER(handle) = ?", handle.downcase)
          Rails.logger.info "Found User: #{user&.id}"
          
          unless user
            Rails.logger.warn "Handle not found: #{handle}"
            return render json: {
              status: 'error',
              message: 'Handle not found'
            }, status: :unprocessable_entity
          end

          verification_data = generate_device_verification(user, device_data)
          Rails.logger.info "Generated verification data: #{verification_data.inspect}"
          
          masked_phone = "...#{user.phone[-4..-1]}"
          if TwilioService.send_verification_code(user.phone, verification_data[:code])
            Rails.logger.info "Verification code sent successfully to #{user.phone}"
            render json: {
              status: 'pending_verification',
              message: "Enter the verification code sent to #{masked_phone}",
              expires_at: verification_data[:expires_at]
            }
          else
            Rails.logger.error "Failed to send verification code to #{user.phone}"
            render json: {
              status: 'error',
              message: 'Failed to send verification code'
            }, status: :service_unavailable
          end
        rescue => e
          Rails.logger.error "Verify GUID error: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          render json: {
            status: 'error',
            message: 'Failed to verify GUID'
          }, status: :internal_server_error
        end
      end

      def verify_guid_code
        Rails.logger.info "=== VERIFY GUID CODE START ==="
        Rails.logger.info "Params: #{params.inspect}"
        
        begin
          code = params[:code].to_s.strip.upcase
          device_data = JSON.parse(request.headers['HTTP_X_DEVICE_DATA'] || '{}')
          fingerprint = DeviceRecognitionService.generate_fingerprint(device_data)
          
          if verify_and_process_code(code, fingerprint, :device)
            render json: {
              status: 'authenticated',
              redirect_to: '/dashboard'
            }
          else
            render json: {
              status: 'error',
              message: 'Invalid verification code'
            }, status: :unprocessable_entity
          end
        rescue => e
          Rails.logger.error "Verify GUID code error: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          render json: {
            status: 'error',
            message: 'Failed to verify code'
          }, status: :internal_server_error
        end
      end

      def logout
        Rails.logger.info "=== LOGOUT START ==="
        if current_device
          device_info = current_device.device_info
          hardware_data = {
            platform: device_info['platform'],
            screen: device_info['screen'],
            memory: device_info.dig('specs', 'memory'),
            cores: device_info.dig('specs', 'cores')
          }
          
          cookies[:device_fingerprint] = {
            value: DeviceRecognitionService.generate_fingerprint(hardware_data),
            expires: 30.days.from_now,
            httponly: true
          }
          
          current_device.update(active: false)
          cookies.delete(:device_token)
        end
        
        reset_session
        render json: {
          status: 'success',
          message: 'Logged out successfully',
          redirect_to: '/login'
        }
      end

      private

      def user_authenticated?
        current_user.present?
      end
    end
  end
end
