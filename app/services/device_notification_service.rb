class DeviceNotificationService
  class << self
    def notify_verification_request(device, code, custom_message = nil)
      return unless device&.active?

      message = {
        type: 'verification_request',
        code: code,
        message: custom_message || 'New device requesting access',
        expires_at: 10.minutes.from_now,
        device_info: {
          type: device.device_type,
          last_active: device.last_active_at
        }
      }

      ActionCable.server.broadcast(
        "device_channel_#{device.id}",
        message
      )

      Rails.logger.info "Verification request sent to device: #{device.id}"
      Rails.logger.debug "Message: #{message.inspect}"
    rescue => e
      Rails.logger.error "Failed to notify device #{device.id}: #{e.message}"
      raise NotificationError, "Failed to send verification request: #{e.message}"
    end
  end

  class NotificationError < StandardError; end
end
