class Job < ApplicationRecord
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

  def can_download?
    # Remove payment check for free tier - everyone can download
    done? && artifact_dir.present? && File.exist?(File.join(artifact_dir, 'images'))
  end

  def zip_path
    return nil unless can_download?
    File.join(artifact_dir, 'imagesweep.zip')
  end

  def manifest_path
    return nil unless can_download?
    File.join(artifact_dir, 'manifest.json')
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
