module Api
  module V1
    class UserController < BaseController
      def data
        if current_user
          render json: {
            handle: current_user.handle,
            phone: current_user.phone,
            devices: current_user.devices.map { |device|
              {
                id: device.id,
                device_type: device.device_type,
                last_active_at: device.last_active_at,
                is_current: device == current_device
              }
            }
          }
        else
          render json: { 
            error: 'Unauthorized'
          }, status: :unauthorized
        end
      end
    end
  end
end
