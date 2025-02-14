module Api
  module V1
    class BaseController < ApplicationController
      protect_from_forgery with: :null_session
      before_action :set_cors_headers
      
      protected


      def handle_options_request
        if request.method == 'OPTIONS'
          headers['Access-Control-Allow-Origin'] = request.origin
          headers['Access-Control-Allow-Methods'] = 'POST, GET, OPTIONS'
          headers['Access-Control-Allow-Headers'] = 'Content-Type, X-CSRF-Token'
          headers['Access-Control-Allow-Credentials'] = 'true'
          headers['Access-Control-Max-Age'] = '1728000'
          render text: '', content_type: 'text/plain'
        end
      end
      
      def authenticate_user!
        return if controller_name == 'debug'  # Skip auth for debug controller
        
        unless current_user
          render json: { error: 'Unauthorized' }, status: :unauthorized
        end
      end

      def current_user
        return @current_user if defined?(@current_user)
        
        if cookies[:device_database_path].present?
          db_path = cookies[:device_database_path]
          if File.exist?(Rails.root.join(db_path))
            device_info = read_device_info(db_path)
            if device_info['device_id'] && device_info['verified'] == 'true'
              device = Device.find_by(device_id: device_info['device_id'], active: true)
              @current_user = device&.user
              session[:user_id] = @current_user.id if @current_user
            end
          end
        end
        @current_user
      end

      def render_error(message, status = :unprocessable_entity)
        render json: { error: message }, status: status
      end

      private

      def set_cors_headers
        headers['Access-Control-Allow-Origin'] = request.origin
        headers['Access-Control-Allow-Methods'] = 'POST, GET, OPTIONS'
        headers['Access-Control-Allow-Headers'] = '*'
        headers['Access-Control-Allow-Credentials'] = 'true'
        headers['Access-Control-Expose-Headers'] = 'X-Set-Storage'
      end

      def read_device_info(db_path)
        db = SQLite3::Database.new(Rails.root.join(db_path).to_s)
        db.results_as_hash = true
        info = db.execute("SELECT * FROM device_info")
                .each_with_object({}) { |row, hash| hash[row['key']] = row['value'] }
        db.close
        info
      rescue SQLite3::Exception => e
        Rails.logger.error "Database read error: #{e.message}"
        {}
      end
    end
  end
end
