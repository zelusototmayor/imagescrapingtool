class UrlValidator
  DISALLOWED_HOSTS = %w[
    localhost
    127.0.0.1
    0.0.0.0
    ::1
  ].freeze

  RFC1918_RANGES = [
    IPAddr.new('10.0.0.0/8'),
    IPAddr.new('172.16.0.0/12'),
    IPAddr.new('192.168.0.0/16')
  ].freeze

  def self.valid?(url_string)
    new(url_string).valid?
  end

  def self.normalize(url_string)
    new(url_string).normalize
  end

  def initialize(url_string)
    @url_string = url_string
  end

  def valid?
    return false unless valid_uri?
    return false if disallowed_host?
    return false if private_ip?
    true
  end

  def normalize
    return nil unless valid?
    
    uri = URI.parse(@url_string)
    uri.path = '/' if uri.path.empty?
    uri.fragment = nil
    uri.to_s
  end

  def origin
    return nil unless valid?
    
    uri = URI.parse(@url_string)
    "#{uri.scheme}://#{uri.host}#{uri.port != uri.default_port ? ":#{uri.port}" : ''}"
  end

  private

  def valid_uri?
    uri = URI.parse(@url_string)
    uri.is_a?(URI::HTTP) && !uri.host.nil?
  rescue URI::InvalidURIError
    false
  end

  def disallowed_host?
    uri = URI.parse(@url_string)
    DISALLOWED_HOSTS.include?(uri.host.downcase)
  rescue
    false
  end

  def private_ip?
    uri = URI.parse(@url_string)
    return false unless uri.host

    begin
      addr = IPAddr.new(uri.host)
      return true if addr.loopback?
      return true if addr.link_local?
      RFC1918_RANGES.any? { |range| range.include?(addr) }
    rescue IPAddr::Error
      false
    end
  rescue
    false
  end
end