class User < ApplicationRecord
  has_many :devices
  
  validates :handle, uniqueness: { case_sensitive: false }, 
            format: { with: /\A@[a-zA-Z0-9_]+\z/, message: "must start with @ and contain only letters and numbers" }
  validates :phone, presence: true, uniqueness: true
  
  before_validation :normalize_handle

  def self.find_by_identifier(identifier)
    if identifier.start_with?('@')
      find_by(handle: identifier)
    else
      find_by(phone: identifier)
    end
  end

  def self.mask_phone(phone)
    return nil unless phone
    "*******#{phone.last(4)}"
  end

  def masked_phone
    self.class.mask_phone(phone)
  end

  private

  def normalize_handle
    if handle.present?
      # Remove any extra @ symbols and ensure single @
      self.handle = "@#{handle.gsub('@', '')}"
    end
  end
end
