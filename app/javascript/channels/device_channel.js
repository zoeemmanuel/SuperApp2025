import consumer from "./consumer"

const deviceChannel = consumer.subscriptions.create("DeviceChannel", {
  connected() {
    console.log("Connected to device channel")
  },

  disconnected() {
    console.log("Disconnected from device channel")
  },

  received(data) {
    console.log("Received message:", data)
    
    if (window.Dashboard) {
      switch(data.type) {
        case 'sync_complete':
          window.Dashboard.handleSyncComplete?.(data)
          break
        case 'verification_request':
          window.Dashboard.handleVerificationRequest?.(data)
          break
        case 'device_update':
          window.Dashboard.handleDeviceUpdate?.(data)
          break
      }
    }
  }
})

export default deviceChannel
