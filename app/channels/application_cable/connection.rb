module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user, :current_device

    def connect
      self.current_device = find_device
      self.current_user = current_device&.user
      reject_unauthorized_connection unless current_user
    end

    private

    def find_device
      device_token = cookies[:device_token]
      return nil unless device_token
      Device.find_by(device_id: device_token)
    end
  end
end
