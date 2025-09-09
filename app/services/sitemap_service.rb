require 'nokogiri'

class SitemapService
  USER_AGENT = ENV.fetch('USER_AGENT', 'ImageSweepBot/0.1 (contact: support@imagesweep.app)')
  SITEMAP_TIMEOUT = ENV.fetch('SITEMAP_DOWNLOAD_TIMEOUT', 30).to_i
  MAX_SITEMAP_SIZE = ENV.fetch('MAX_SITEMAP_SIZE', 10.megabytes).to_i
  
  def initialize
    @visited_sitemaps = Set.new
  end

  def self.fetch_filtered_urls(starting_url, job)
    service = new
    urls = service.fetch_sitemap_urls(starting_url)
    return nil if urls.nil? || urls.empty?
    
    service.filter_urls_for_mode(urls, job)
  end

  def fetch_sitemap_urls(starting_url)
    domain = extract_domain(starting_url)
    return nil unless domain

    Rails.logger.info "Fetching sitemap for domain: #{domain}"
    
    sitemap_url = "#{domain}/sitemap.xml"
    sitemap_content = fetch_sitemap(sitemap_url)
    
    return nil unless sitemap_content
    
    parse_sitemap(sitemap_content)
  end

  def fetch_sitemap(sitemap_url)
    Rails.logger.debug "Attempting to fetch sitemap from: #{sitemap_url}"
    
    return nil if @visited_sitemaps.include?(sitemap_url)
    @visited_sitemaps << sitemap_url
    
    begin
      response = Faraday.get(sitemap_url) do |req|
        req.headers['User-Agent'] = USER_AGENT
        req.options.timeout = SITEMAP_TIMEOUT
        req.options.open_timeout = 10
      end
      
      if response.success?
        content_length = response.body.bytesize
        if content_length > MAX_SITEMAP_SIZE
          Rails.logger.warn "Sitemap too large (#{content_length} bytes), skipping: #{sitemap_url}"
          return nil
        end
        
        Rails.logger.info "Successfully fetched sitemap: #{sitemap_url} (#{content_length} bytes)"
        return response.body
      else
        Rails.logger.info "Sitemap not found (HTTP #{response.status}): #{sitemap_url}"
        return nil
      end
    rescue Faraday::TimeoutError => e
      Rails.logger.warn "Sitemap fetch timed out: #{sitemap_url} - #{e.message}"
      return nil
    rescue Faraday::Error, StandardError => e
      Rails.logger.warn "Error fetching sitemap: #{sitemap_url} - #{e.class.name}: #{e.message}"
      return nil
    end
  end

  def filter_urls_for_mode(urls, job)
    return [] if urls.empty?
    
    Rails.logger.info "Filtering #{urls.length} URLs for job mode: #{job.scrape_mode}"
    
    filtered_urls = case job.scrape_mode
    when 'subpath_only'
      filter_subpath_urls(urls, job.url)
    when 'entire_website' 
      filter_same_domain_urls(urls, job.url)
    else
      Rails.logger.warn "Unknown scrape mode: #{job.scrape_mode}"
      []
    end
    
    # Apply page limits
    max_pages = case job.scrape_mode
    when 'subpath_only'
      25 # SUBPATH_MAX_PAGES from ImageScraper
    when 'entire_website'
      50 # ENTIRE_WEBSITE_MAX_PAGES from ImageScraper
    else
      25
    end
    
    result = filtered_urls.first(max_pages)
    Rails.logger.info "Filtered to #{result.length} URLs (limit: #{max_pages})"
    result
  end

  private

  def extract_domain(url)
    uri = URI.parse(url)
    return nil unless uri.scheme && uri.host
    "#{uri.scheme}://#{uri.host}#{uri.port != uri.default_port ? ":#{uri.port}" : ""}"
  rescue URI::InvalidURIError => e
    Rails.logger.error "Invalid URL provided: #{url} - #{e.message}"
    nil
  end

  def parse_sitemap(xml_content)
    Rails.logger.debug "Parsing sitemap XML content"
    
    begin
      doc = Nokogiri::XML(xml_content)
      
      if doc.errors.any?
        Rails.logger.warn "XML parsing warnings: #{doc.errors.map(&:message).join(', ')}"
      end
      
      urls = []
      
      # Handle regular sitemap format - use CSS selector for better compatibility
      doc.css('url loc').each do |loc_node|
        url = loc_node.text.strip
        next if url.empty?
        
        if valid_url?(url)
          urls << url
        else
          Rails.logger.debug "Skipping invalid URL from sitemap: #{url}"
        end
      end
      
      Rails.logger.info "Extracted #{urls.length} URLs from sitemap"
      urls.uniq
      
    rescue Nokogiri::XML::SyntaxError => e
      Rails.logger.error "Malformed XML in sitemap: #{e.message}"
      []
    rescue StandardError => e
      Rails.logger.error "Error parsing sitemap XML: #{e.class.name}: #{e.message}"
      []
    end
  end

  def valid_url?(url)
    return false if url.nil? || url.empty?
    
    uri = URI.parse(url)
    uri.scheme && uri.host && (uri.scheme == 'http' || uri.scheme == 'https')
  rescue URI::InvalidURIError
    false
  end

  def filter_subpath_urls(urls, starting_url)
    starting_uri = URI.parse(starting_url)
    starting_path = starting_uri.path.chomp('/')
    
    urls.select do |url|
      begin
        uri = URI.parse(url)
        # Same domain and within the starting path
        uri.scheme == starting_uri.scheme &&
        uri.host == starting_uri.host &&
        uri.port == starting_uri.port &&
        uri.path.start_with?(starting_path)
      rescue URI::InvalidURIError
        false
      end
    end
  rescue URI::InvalidURIError => e
    Rails.logger.error "Invalid starting URL: #{starting_url} - #{e.message}"
    []
  end

  def filter_same_domain_urls(urls, starting_url)
    starting_uri = URI.parse(starting_url)
    
    urls.select do |url|
      begin
        uri = URI.parse(url)
        # Same domain only
        uri.scheme == starting_uri.scheme &&
        uri.host == starting_uri.host &&
        uri.port == starting_uri.port
      rescue URI::InvalidURIError
        false
      end
    end
  rescue URI::InvalidURIError => e
    Rails.logger.error "Invalid starting URL: #{starting_url} - #{e.message}"
    []
  end
end