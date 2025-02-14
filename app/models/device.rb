class Device < ApplicationRecord
  belongs_to :user
  has_one :device_database, dependent: :destroy
  
  validates :device_id, presence: true, uniqueness: true
  validates :system_id, presence: true, uniqueness: { scope: :user_id }
  validates :device_type, presence: true, inclusion: { in: %w[desktop mobile tablet] }
  validates :device_info, presence: true
  
  scope :active, -> { where(active: true) }
  
  before_validation :ensure_device_info_structure
  before_create :ensure_active_and_timestamp
  after_create :setup_device_database
  after_save :sync_if_changed

  def link_to_user(user)
    transaction do
      update!(user: user)
      verify_relationships
    end
  end

  def verify_relationships
    # Link any devices with same system_id to this user
    Device.where(system_id: system_id)
          .where.not(id: id)
          .update_all(user_id: user_id)
  end

  def local_db_path
    return nil unless device_database&.path
    Rails.root.join(device_database.path).to_s
  end

  def add_browser!(user_agent, request_headers = {})
    return unless user_agent.present?

    browser_info = parse_browser_info(user_agent)
    
    current_browsers = device_info['browsers'] || []
    existing_browser = current_browsers.find { |b| b['name'] == browser_info[:name] }
    
    if existing_browser
      existing_browser.merge!(
        'version' => browser_info[:version],
        'last_seen' => Time.current.iso8601
      )
    else
      current_browsers << {
        'name' => browser_info[:name],
        'version' => browser_info[:version],
        'last_seen' => Time.current.iso8601
      }
    end

    update!(
      device_info: device_info.merge('browsers' => current_browsers),
      last_active_at: Time.current
    )
  end

  def sync_if_changed
    sync_with_cloud! if saved_changes.any?
  end

  def sync_with_cloud!
    return unless device_database&.sync_token.present?
    ReplicationService.sync_device(self)
  end
  
  private
  
  def ensure_device_info_structure
    return if device_info.blank?
    
    self.device_info = {
      'created_at' => device_info['created_at'] || Time.current.iso8601,
      'browsers' => device_info['browsers'] || []
    }
  end
  
  def ensure_active_and_timestamp
    self.active = true if active.nil?
    self.last_active_at ||= Time.current
  end
  
  def setup_device_database
    DeviceService.setup_device_database(self)
  end

  def parse_browser_info(user_agent)
    ua = user_agent.downcase
    {
      name: detect_browser_name(ua),
      version: detect_browser_version(ua)
    }
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
end
