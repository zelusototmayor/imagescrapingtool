class RobotsChecker
  def self.allowed?(url, user_agent = ENV.fetch('USER_AGENT', 'ImageSweepBot/0.1'))
    new(url, user_agent).allowed?
  end

  def initialize(url, user_agent)
    @url = URI.parse(url)
    @user_agent = user_agent
    @robots = nil
  end

  def allowed?
    load_robots
    return true if @robots.nil?
    
    @robots.allowed?(@url.path, @user_agent)
  rescue => e
    Rails.logger.warn "Robots.txt check failed for #{@url}: #{e.message}"
    true
  end

  private

  def load_robots
    robots_url = "#{@url.scheme}://#{@url.host}#{@url.port != @url.default_port ? ":#{@url.port}" : ''}/robots.txt"
    
    Rails.logger.debug "Loading robots.txt from #{robots_url}"
    
    # Use Timeout to prevent hanging
    Timeout.timeout(10) do # 10 second max for robots.txt
      response = Faraday.get(robots_url) do |req|
        req.options.timeout = 8 # Faraday timeout
        req.options.open_timeout = 5 # Connection timeout
        req.headers['User-Agent'] = @user_agent
      end

      if response.success?
        Rails.logger.debug "Successfully loaded robots.txt from #{robots_url}"
        @robots = Robotex.new(@user_agent)
        @robots.parse(robots_url, response.body)
      else
        Rails.logger.debug "robots.txt returned non-success status: #{response.status}"
      end
    end
  rescue Timeout::Error => e
    Rails.logger.warn "robots.txt check timed out for #{robots_url}: #{e.message}"
    @robots = nil
  rescue => e
    Rails.logger.debug "Could not load robots.txt from #{robots_url}: #{e.message}"
    @robots = nil
  end
end