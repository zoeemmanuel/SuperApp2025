module Api
  module V1
    class DeviceSyncController < BaseController
      before_action :authenticate_user!
      
      def sync
        result = ReplicationService.sync_device(current_device)
        
        if result[:status] == 'success'
          render json: { 
            status: 'success', 
            synced_at: result[:synced_at] 
          }
        else
          render json: { 
            status: 'error', 
            message: result[:message] 
          }, status: :unprocessable_entity
        end
      end

      def status
        render json: {
          device_id: current_device.device_id,
          last_synced_at: current_device.device_database&.last_synced_at,
          sync_status: current_device.device_database&.sync_token.present? ? 'ready' : 'not_configured'
        }
      end
    end
  end
end
