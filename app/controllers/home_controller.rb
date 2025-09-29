class HomeController < ApplicationController
  def index
    if user_signed_in?
      @downloads_used = current_user.downloads_used
      @remaining_downloads = current_user.remaining_downloads
      @is_premium = current_user.premium?
    else
      # For anonymous users, check session-based downloads
      session_id = session.id&.to_s || request.session_options[:id]
      ip_address = request.remote_ip
      anonymous_downloads = Download.anonymous
                                   .for_session(session_id)
                                   .for_ip(ip_address)
                                   .count
      @anonymous_downloads_used = anonymous_downloads
      @anonymous_remaining = [1 - anonymous_downloads, 0].max
    end
  end

  def pricing
  end
end