module Api
  module V1
    class DevicesController < BaseController
      before_action :authenticate_user!
      skip_before_action :verify_authenticity_token, only: [:reset]

      def index
        devices = current_user.devices
          .includes(:device_database)
          .order(last_active_at: :desc)

        render json: {
          handle: current_user.handle.sub(/^@+/, '@'),
          phone: current_user.phone,
          devices: devices.map { |device| device_json(device) }
        }
      end

      def reset
        Rails.logger.info "=== RESET DEVICES START ==="
        
        begin
          ActiveRecord::Base.transaction do
            user_to_reset = current_user
            devices_to_reset = user_to_reset.devices
            deactivated_count = 0

            Rails.logger.info "Found #{devices_to_reset.count} devices to reset"
            
            # Clean up each device and its database
            devices_to_reset.each do |device|
              Rails.logger.info "Processing device: #{device.id}"
              
              # Handle device database cleanup
              if device.device_database&.path
                db_path = Rails.root.join(device.device_database.path)
                if File.exist?(db_path)
                  begin
                    FileUtils.rm_f(db_path)
                    Rails.logger.info "Deleted database file: #{db_path}"
                  rescue => e
                    Rails.logger.error "Database deletion error: #{e.message}"
                  ensure
                    device.device_database.destroy!
                  end
                end
              end

              # Destroy the device
              device.destroy!
              deactivated_count += 1
              Rails.logger.info "Successfully deleted device: #{device.id}"
            end

            # Clean up user's session and authentication
            reset_session
            cookies.delete(:device_token, domain: request.domain)
            cookies.delete(:device_database_path, domain: request.domain)
            cookies.delete(:verification_id, domain: request.domain)
            
            # Delete the user
            user_to_reset.destroy!
            Rails.logger.info "Successfully deleted user: #{user_to_reset.id}"

            # Signal frontend to clear storage
            response.headers['Clear-Local-Storage'] = 'true'
            response.headers['X-Reset-Complete'] = 'true'

            Rails.logger.info "Successfully reset and deleted all data"
            
            render json: { 
              status: 'success',
              message: 'Account and all devices have been deleted',
              deactivated_count: deactivated_count,
              clear_storage: true,
              redirect_to: '/login'
            }
          end
        rescue => e
          Rails.logger.error "Reset error: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          render json: {
            status: 'error',
            message: 'Failed to reset account'
          }, status: :unprocessable_entity
        end
      end

      def status
        device_db = current_device.device_database
        if device_db.nil?
          DeviceService.setup_device_database(current_device)
          device_db = current_device.device_database.reload
        end

        render json: {
          device_id: current_device.device_id,
          device_type: current_device.device_type,
          device_info: current_device.device_info,
          last_active_at: current_device.last_active_at,
          last_synced_at: device_db.last_synced_at,
          db_path: device_db.path,
          sync_status: device_db.sync_token.present? ? 'ready' : 'not_configured'
        }
      end

      def sync
        begin
          result = ReplicationService.sync_device(current_device)
          render json: { 
            status: 'success',
            sync_status: result 
          }
        rescue => e
          Rails.logger.error "Device sync error: #{e.message}"
          render json: {
            status: 'error',
            message: 'Failed to sync device'
          }, status: :unprocessable_entity
        end
      end

      private

      def device_json(device)
        current = device.id == current_device&.id
        
        {
          id: device.id,
          device_id: device.device_id,
          device_type: device.device_type,
          device_info: device.device_info.merge(
            'current_browser' => device.current_browser
          ),
          last_active_at: device.last_active_at,
          is_current: current,
          browser_count: device.device_info['browsers']&.length || 0
        }
      end
    end
  end
end
