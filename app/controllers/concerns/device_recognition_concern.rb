module DeviceRecognitionConcern
  extend ActiveSupport::Concern

  included do
    before_action :process_device_recognition
    helper_method :current_device_info if respond_to?(:helper_method)
  end

  private

  def process_device_recognition
    return unless request.format.json? || request.format.html?
    
    # Process browser identification if header present
    browser_token = request.headers['X-Browser-Token']
    validate_browser_token(browser_token) if browser_token.present?
    
    # Process device data if present
    if params[:device_data].present?
      @device_data = sanitize_device_data(params[:device_data])
      update_device_info if current_device
    end
  end

  def sanitize_device_data(data)
    return {} unless data.is_a?(Hash)

    data = data.respond_to?(:to_unsafe_h) ? data.to_unsafe_h : data.to_h
    
    {
      'hardware' => {
        'platform' => data.dig('hardware', 'platform'),
        'cpuCores' => data.dig('hardware', 'cpuCores'),
        'memory' => data.dig('hardware', 'memory'),
        'architecture' => data.dig('hardware', 'architecture')
      }.compact,
      'browser' => {
        'userAgent' => data.dig('browser', 'userAgent'),
        'language' => data.dig('browser', 'language')
      }.compact,
      'screen' => data.dig('screen'),
      'database' => data.dig('database')
    }.compact
  end

  def validate_browser_token(token)
    return unless current_device&.device_database
    
    unless current_device.device_database.verified_for_browser?(token)
      current_device.device_database.register_browser_token(token)
    end
  end

  def update_device_info
    return unless @device_data&.dig('browser', 'userAgent')
    
    browser_info = parse_browser_info(@device_data['browser']['userAgent'])
    current_device.add_browser!(
      @device_data['browser']['userAgent'],
      browser_info
    )
  end

  def parse_browser_info(user_agent)
    return {} unless user_agent

    ua = user_agent.downcase
    info = {
      name: detect_browser_name(ua),
      version: detect_browser_version(ua),
      os: detect_os(ua)
    }

    info[:mobile] = true if ua =~ /mobile|android|iphone|ipad|ipod/i
    info[:bot] = true if ua =~ /bot|crawler|spider|slurp/i

    info.compact
  end

  def detect_browser_name(ua)
    case ua
    when /edg\//i then 'Edge'
    when /chrome/i then 'Chrome'
    when /firefox/i then 'Firefox'
    when /safari/i then 'Safari'
    when /opera|opr/i then 'Opera'
    else 'Unknown'
    end
  end

  def detect_browser_version(ua)
    case detect_browser_name(ua)
    when 'Edge'
      ua.match(/edg\/(\d+(\.\d+)*)/i)&.captures&.first
    when 'Chrome'
      ua.match(/chrome\/(\d+(\.\d+)*)/i)&.captures&.first
    when 'Firefox'
      ua.match(/firefox\/(\d+(\.\d+)*)/i)&.captures&.first
    when 'Safari'
      ua.match(/version\/(\d+(\.\d+)*)/i)&.captures&.first
    when 'Opera'
      ua.match(/opr\/(\d+(\.\d+)*)/i)&.captures&.first ||
        ua.match(/opera\/(\d+(\.\d+)*)/i)&.captures&.first
    end
  end

  def detect_os(ua)
    os_info = case ua
    when /windows nt/i
      version = ua.match(/windows nt (\d+(\.\d+)*)/i)&.captures&.first
      { name: 'Windows', version: version }
    when /mac os x/i
      version = ua.match(/mac os x (\d+[._]\d+[._]\d+)/i)&.captures&.first&.tr('_', '.')
      { name: 'macOS', version: version }
    when /android/i
      version = ua.match(/android (\d+(\.\d+)*)/i)&.captures&.first
      { name: 'Android', version: version }
    when /ios|iphone|ipad/i
      version = ua.match(/os (\d+[._]\d+[._]\d+)/i)&.captures&.first&.tr('_', '.')
      { name: 'iOS', version: version }
    when /linux/i
      { name: 'Linux' }
    else
      { name: 'Unknown' }
    end

    os_info.compact
  end
end
