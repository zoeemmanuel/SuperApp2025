class DeviceChannel < ApplicationCable::Channel
  def subscribed
    stream_from "device_channel_#{current_device.id}"
  end

  def unsubscribed
    stop_all_streams
  end

  def receive(data)
    case data['action']
    when 'sync_complete'
      broadcast_sync_complete(data)
    when 'device_update'
      broadcast_device_update(data)
    end
  end

  private

  def broadcast_sync_complete(data)
    ActionCable.server.broadcast("device_channel_#{current_device.id}", {
      type: 'sync_complete',
      status: data['status'],
      synced_at: Time.current
    })
  end

  def broadcast_device_update(data)
    ActionCable.server.broadcast("device_channel_#{current_device.id}", {
      type: 'device_update',
      device: data['device']
    })
  end
end
