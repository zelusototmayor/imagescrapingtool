class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    @user = current_user
    @recent_jobs = current_user.jobs.recent.limit(10)
    @downloads_used = current_user.downloads_used
    @remaining_downloads = current_user.remaining_downloads
    @is_premium = current_user.premium?
  end
end