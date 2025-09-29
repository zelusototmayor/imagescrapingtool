class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :jobs, dependent: :destroy
  has_many :downloads, dependent: :destroy

  enum :subscription_status, {
    free: 0,
    premium: 1
  }

  FREE_DOWNLOAD_LIMIT = 2

  def download_limit_reached?
    return false if premium?
    downloads_used >= FREE_DOWNLOAD_LIMIT
  end

  def can_download?
    premium? || !download_limit_reached?
  end

  def remaining_downloads
    return Float::INFINITY if premium?
    [FREE_DOWNLOAD_LIMIT - downloads_used, 0].max
  end

  def increment_downloads!
    increment!(:downloads_used)
  end
end
