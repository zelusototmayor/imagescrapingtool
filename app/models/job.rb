class Job < ApplicationRecord
  belongs_to :user, optional: true
  has_many :downloads, dependent: :destroy

  enum :status, {
    queued: 0,
    running: 1,
    done: 2,
    error: 3
  }

  enum :scrape_mode, {
    current_page: 0,
    subpath_only: 1,
    entire_website: 2
  }

  before_create :generate_uuid
  before_create :set_artifact_dir

  validates :url, presence: true
  validate :valid_url, if: -> { url.present? }
  validates :scrape_mode, presence: true, inclusion: { in: scrape_modes.keys }
  validates :progress, numericality: { in: 0..100 }
  validates :uuid, uniqueness: true, allow_nil: true

  scope :recent, -> { order(created_at: :desc) }
  scope :completed_or_errored, -> { where(status: [:done, :error]) }
  scope :old, ->(days = 1) { where('created_at < ?', days.days.ago) }

  def job_id
    uuid
  end

  def can_download?(current_user = nil, session_id = nil, ip_address = nil)
    return false unless done? && artifact_dir.present? && File.exist?(File.join(artifact_dir, 'images'))

    # If user is signed in and premium, they can always download
    return true if current_user&.premium?

    # Check if this specific job has already been downloaded
    return false if already_downloaded?(current_user, session_id, ip_address)

    # Check download limits
    if current_user
      # Signed in user - check their download limit
      current_user.can_download?
    else
      # Anonymous user - check session-based limit
      anonymous_downloads_count = Download.anonymous
                                         .for_session(session_id)
                                         .for_ip(ip_address)
                                         .count
      anonymous_downloads_count < 1
    end
  end

  def already_downloaded?(current_user = nil, session_id = nil, ip_address = nil)
    if current_user
      downloads.for_user(current_user).exists?
    else
      downloads.anonymous.for_session(session_id).for_ip(ip_address).exists?
    end
  end

  def zip_path(current_user = nil, session_id = nil, ip_address = nil)
    return nil unless can_download?(current_user, session_id, ip_address)
    File.join(artifact_dir, 'imagesweep.zip')
  end

  def manifest_path(current_user = nil, session_id = nil, ip_address = nil)
    return nil unless can_download?(current_user, session_id, ip_address)
    File.join(artifact_dir, 'manifest.json')
  end

  def record_download!(current_user = nil, session_id = nil, ip_address = nil)
    download = downloads.create!(
      user: current_user,
      ip_address: ip_address,
      session_id: session_id,
      downloaded_at: Time.current
    )

    current_user&.increment_downloads!
    download
  end

  def cleanup_artifacts!
    return unless artifact_dir.present?
    FileUtils.rm_rf(artifact_dir) if File.exist?(artifact_dir)
  end

  private

  def generate_uuid
    self.uuid = SecureRandom.uuid
  end

  def set_artifact_dir
    self.artifact_dir = File.join(Rails.root, 'storage', 'imagesweep', uuid) if uuid.present?
  end

  def valid_url
    return if url.blank?
    
    unless UrlValidator.valid?(url)
      errors.add(:url, 'is not a valid URL or is not allowed')
    end
    
    self.url = UrlValidator.normalize(url) if errors[:url].empty?
  end
end
