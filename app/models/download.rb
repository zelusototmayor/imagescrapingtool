class Download < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :job

  validates :ip_address, presence: true
  validates :session_id, presence: true

  scope :anonymous, -> { where(user: nil) }
  scope :for_user, ->(user) { where(user: user) }
  scope :for_session, ->(session_id) { where(session_id: session_id) }
  scope :for_ip, ->(ip) { where(ip_address: ip) }

  def anonymous?
    user.nil?
  end
end
