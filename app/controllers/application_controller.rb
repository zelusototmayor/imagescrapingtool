class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Devise authentication helpers
  before_action :configure_permitted_parameters, if: :devise_controller?

  private

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:email])
    devise_parameter_sanitizer.permit(:account_update, keys: [:email])
  end

  def health
    begin
      # Check browser process count
      chromium_count = `pgrep -c -f 'chromium.*--headless' 2>/dev/null || echo 0`.strip.to_i
      chrome_count = `pgrep -c -f 'chrome.*--headless' 2>/dev/null || echo 0`.strip.to_i
      total_browser_processes = chromium_count + chrome_count

      # Check Redis connectivity
      redis_healthy = Sidekiq.redis { |conn| conn.ping == "PONG" } rescue false

      # Check database connectivity
      db_healthy = Job.connection.active? rescue false

      # Check running jobs
      running_jobs = Job.running.count

      health_data = {
        status: "ok",
        timestamp: Time.current.iso8601,
        browser_processes: {
          chromium: chromium_count,
          chrome: chrome_count,
          total: total_browser_processes
        },
        services: {
          redis: redis_healthy,
          database: db_healthy
        },
        jobs: {
          running: running_jobs
        }
      }

      # Warn if too many browser processes
      if total_browser_processes > 10
        health_data[:warnings] = ["High browser process count: #{total_browser_processes}"]
      end

      # Set error status if critical services are down
      unless redis_healthy && db_healthy
        health_data[:status] = "error"
        render json: health_data, status: 503
        return
      end

      render json: health_data, status: 200
    rescue => e
      render json: {
        status: "error",
        timestamp: Time.current.iso8601,
        error: e.message
      }, status: 500
    end
  end
end
