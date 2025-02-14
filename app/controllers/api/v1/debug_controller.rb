module Api
  module V1
    class DebugController < BaseController
      def state
        device = Device.find_by(device_id: cookies[:device_token], active: true) if cookies[:device_token].present?
        
        render json: {
          request_info: {
            host: request.host,
            ip: request.remote_ip,
            user_agent: request.user_agent,
            ssl: request.ssl?,
            path: request.path,
            format: request.format.to_s
          },
          storage: {
            device_token: cookies[:device_token],
            device_database_path: cookies[:device_database_path],
            ip_specific_path: cookies["device_database_path_#{request.host.gsub('.', '_')}"],
            all_cookies: cookies.to_h
          },
          device_info: device ? {
            id: device.id,
            device_id: device.device_id,
            user_id: device.user_id,
            active: device.active,
            database_path: device.device_database&.path
          } : nil,
          user_info: current_user ? {
            id: current_user.id,
            handle: current_user.handle,
            verified: current_user.verified
          } : nil,
          browser_info: {
            user_agent: request.user_agent,
            accept_language: request.accept_language,
            content_type: request.content_type,
            headers: {
              origin: request.headers['Origin'],
              referer: request.headers['Referer']
            }
          }
        }
      end

      def cookie_info
        render json: {
          cookies: cookies.to_h,
          headers: {
            user_agent: request.user_agent,
            host: request.host,
            origin: request.headers['Origin'],
            referer: request.headers['Referer']
          }
        }
      end
    end
  end
end
