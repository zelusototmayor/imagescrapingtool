class Rack::Attack
  redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
  Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(url: redis_url)

  throttle('jobs/ip', limit: ENV.fetch('RATE_LIMIT_JOBS_PER_HOUR', 100).to_i, period: 1.hour) do |req|
    req.ip if req.path == '/jobs' && req.post?
  end
  
  # Allow unlimited requests from localhost in development
  safelist('local-development') do |req|
    Rails.env.development? && ['127.0.0.1', '::1', 'localhost'].include?(req.ip)
  end

  self.throttled_responder = lambda do |_request|
    [
      429,
      { 'Content-Type' => 'application/json' },
      [{ error: 'Rate limit exceeded. Please try again later.' }.to_json]
    ]
  end
end

Rails.application.config.middleware.use Rack::Attack