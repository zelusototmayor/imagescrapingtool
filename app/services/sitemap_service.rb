require 'nokogiri'
require 'digest'

class SitemapService
  USER_AGENT = ENV.fetch('USER_AGENT', 'ImageSweepBot/0.1 (contact: support@imagesweep.app)')
  SITEMAP_TIMEOUT = ENV.fetch('SITEMAP_DOWNLOAD_TIMEOUT', 30).to_i
  MAX_SITEMAP_SIZE = ENV.fetch('MAX_SITEMAP_SIZE', 10.megabytes).to_i
  SITEMAP_CACHE_TTL = ENV.fetch('SITEMAP_CACHE_TTL', 3600).to_i # 1 hour default
  LARGE_SITEMAP_THRESHOLD = ENV.fetch('LARGE_SITEMAP_THRESHOLD', 1.megabyte).to_i
  
  # URL prioritization weights - configurable via environment
  DEPTH_PENALTY_WEIGHT = ENV.fetch('SITEMAP_DEPTH_PENALTY', 10).to_i
  SIMILARITY_BONUS_WEIGHT = ENV.fetch('SITEMAP_SIMILARITY_BONUS', 30).to_i
  UTILITY_PAGE_PENALTY = ENV.fetch('SITEMAP_UTILITY_PENALTY', 50).to_i
  
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

    memory_start = current_memory_usage
    Rails.logger.info "Fetching sitemap for domain: #{domain} (memory: #{memory_start}MB)"
    
    sitemap_url = "#{domain}/sitemap.xml"
    sitemap_content = fetch_sitemap(sitemap_url)
    
    return nil unless sitemap_content
    
    urls = parse_sitemap(sitemap_content)
    
    memory_end = current_memory_usage
    memory_used = memory_end - memory_start
    Rails.logger.info "Sitemap processing complete: #{urls&.length || 0} URLs, memory used: #{memory_used.round(2)}MB (#{memory_start.round(2)}MB → #{memory_end.round(2)}MB)"
    
    urls
  end

  def fetch_sitemap(sitemap_url)
    Rails.logger.debug "Attempting to fetch sitemap from: #{sitemap_url}"
    
    return nil if @visited_sitemaps.include?(sitemap_url)
    @visited_sitemaps << sitemap_url
    
    # Check Redis cache first
    cache_key = "sitemap:#{Digest::SHA256.hexdigest(sitemap_url)}"
    cached_content = get_cached_sitemap(cache_key)
    if cached_content
      Rails.logger.info "Using cached sitemap: #{sitemap_url}"
      return cached_content
    end
    
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
        
        # Cache the sitemap content
        cache_sitemap(cache_key, response.body)
        
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
    
    # Apply smart prioritization before limiting
    prioritized_urls = prioritize_urls(filtered_urls, job.url)
    
    result = prioritized_urls.first(max_pages)
    Rails.logger.info "Filtered and prioritized to #{result.length} URLs (limit: #{max_pages})"
    result
  end

  def prioritize_urls(urls, starting_url)
    return urls if urls.empty?
    
    Rails.logger.info "Prioritizing #{urls.length} URLs based on importance scoring"
    
    # Score each URL and sort by score (descending - higher scores first)
    scored_urls = urls.map do |url|
      score = score_url_importance(url, starting_url)
      { url: url, score: score }
    end
    
    sorted_urls = scored_urls.sort_by { |item| -item[:score] }
    
    Rails.logger.debug "URL prioritization complete. Top 5 scores: #{sorted_urls.first(5).map { |item| "#{item[:url]} (#{item[:score]})" }.join(', ')}"
    
    sorted_urls.map { |item| item[:url] }
  end

  def score_url_importance(url, starting_url)
    score = 100 # Base score
    
    begin
      uri = URI.parse(url)
      starting_uri = URI.parse(starting_url)
      
      # Depth penalty: deeper URLs are less important
      depth = uri.path.split('/').length - 2 # Remove empty string and domain
      score -= (depth * DEPTH_PENALTY_WEIGHT)
      
      # Similarity bonus: URLs similar to starting URL get higher priority
      if path_similarity_bonus?(uri.path, starting_uri.path)
        score += SIMILARITY_BONUS_WEIGHT
        Rails.logger.debug "Similarity bonus applied to #{url}"
      end
      
      # Utility page penalty: common utility pages get lower priority
      if utility_page?(uri.path)
        score -= UTILITY_PAGE_PENALTY
        Rails.logger.debug "Utility page penalty applied to #{url}"
      end
      
    rescue URI::InvalidURIError => e
      Rails.logger.warn "Invalid URL in scoring: #{url} - #{e.message}"
      score = 0 # Invalid URLs get lowest priority
    end
    
    # Ensure minimum score of 1
    [score, 1].max
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
    Rails.logger.debug "Parsing sitemap XML content (#{xml_content.bytesize} bytes)"
    
    # Use streaming parser for large sitemaps to reduce memory usage
    if xml_content.bytesize > LARGE_SITEMAP_THRESHOLD
      Rails.logger.info "Using streaming parser for large sitemap (#{xml_content.bytesize} bytes)"
      return parse_sitemap_streaming(xml_content)
    end
    
    begin
      doc = Nokogiri::XML(xml_content)
      
      if doc.errors.any?
        Rails.logger.warn "XML parsing warnings: #{doc.errors.map(&:message).join(', ')}"
      end
      
      # Check if this is a sitemap index file
      if doc.css('sitemapindex').any?
        Rails.logger.info "Detected sitemap index file, processing child sitemaps"
        return parse_sitemap_index(doc)
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

  def parse_sitemap_streaming(xml_content)
    Rails.logger.debug "Parsing sitemap using streaming XML parser"
    urls = []
    current_url = nil
    is_sitemap_index = false
    
    begin
      reader = Nokogiri::XML::Reader(xml_content)
      
      reader.each do |node|
        case node.name
        when 'sitemapindex'
          if node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
            is_sitemap_index = true
            Rails.logger.info "Detected sitemap index file via streaming parser"
            break # Exit streaming parser and use regular parser for sitemap index
          end
        when 'loc'
          if node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
            # Read the text content of the <loc> element
            loc_content = node.inner_xml.strip
            if !loc_content.empty? && valid_url?(loc_content)
              urls << loc_content
            elsif !loc_content.empty?
              Rails.logger.debug "Skipping invalid URL from streaming sitemap: #{loc_content}"
            end
          end
        end
        
        # Periodically log progress for very large sitemaps
        if urls.length % 5000 == 0 && urls.length > 0
          Rails.logger.debug "Streaming parser progress: #{urls.length} URLs processed"
        end
      end
      
      # If this was a sitemap index, fall back to regular parsing
      if is_sitemap_index
        Rails.logger.info "Falling back to regular parser for sitemap index"
        return parse_sitemap_without_streaming(xml_content)
      end
      
      Rails.logger.info "Streaming parser extracted #{urls.length} URLs from sitemap"
      urls.uniq
      
    rescue Nokogiri::XML::SyntaxError => e
      Rails.logger.error "Malformed XML in streaming sitemap parser: #{e.message}"
      []
    rescue StandardError => e
      Rails.logger.error "Error in streaming sitemap parser: #{e.class.name}: #{e.message}"
      []
    end
  end

  def parse_sitemap_without_streaming(xml_content)
    # This is the original parse_sitemap logic without streaming check
    begin
      doc = Nokogiri::XML(xml_content)
      
      if doc.errors.any?
        Rails.logger.warn "XML parsing warnings: #{doc.errors.map(&:message).join(', ')}"
      end
      
      # Check if this is a sitemap index file
      if doc.css('sitemapindex').any?
        Rails.logger.info "Processing sitemap index"
        return parse_sitemap_index(doc)
      end
      
      urls = []
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

  def parse_sitemap_index(doc)
    all_urls = []
    sitemap_urls = []
    
    # Extract sitemap URLs from index
    doc.css('sitemap loc').each do |loc_node|
      sitemap_url = loc_node.text.strip
      next if sitemap_url.empty?
      
      if valid_url?(sitemap_url)
        sitemap_urls << sitemap_url
      else
        Rails.logger.debug "Skipping invalid sitemap URL from index: #{sitemap_url}"
      end
    end
    
    Rails.logger.info "Found #{sitemap_urls.length} sitemap references in index"
    
    # Fetch and parse each referenced sitemap
    sitemap_urls.each_with_index do |sitemap_url, index|
      Rails.logger.debug "Processing sitemap #{index + 1}/#{sitemap_urls.length}: #{sitemap_url}"
      
      sitemap_content = fetch_sitemap(sitemap_url)
      next unless sitemap_content
      
      urls = parse_sitemap(sitemap_content)
      if urls.any?
        all_urls.concat(urls)
        Rails.logger.debug "Added #{urls.length} URLs from #{sitemap_url}"
      end
    end
    
    Rails.logger.info "Combined #{all_urls.length} total URLs from sitemap index"
    all_urls.uniq
  end

  def valid_url?(url)
    return false if url.nil? || url.empty?
    
    uri = URI.parse(url)
    uri.scheme && uri.host && (uri.scheme == 'http' || uri.scheme == 'https')
  rescue URI::InvalidURIError
    false
  end

  def filter_subpath_urls(urls, starting_url)
    return [] if urls.empty?
    
    begin
      starting_uri = URI.parse(starting_url)
      starting_domain = "#{starting_uri.scheme}://#{starting_uri.host}#{starting_uri.port != starting_uri.default_port ? ":#{starting_uri.port}" : ""}"
      starting_path = starting_uri.path.chomp('/')
      
      Rails.logger.debug "Filtering #{urls.length} URLs for subpath: #{starting_domain}#{starting_path}"
      
      # Optimized filtering with batch processing and reduced URI parsing
      filtered_urls = []
      urls.each do |url|
        next unless url.start_with?(starting_domain) # Quick domain check before URI parsing
        
        begin
          uri = URI.parse(url)
          if uri.path.start_with?(starting_path)
            filtered_urls << url
          end
        rescue URI::InvalidURIError
          # Skip invalid URLs
        end
      end
      
      Rails.logger.debug "Subpath filtering result: #{filtered_urls.length} URLs"
      filtered_urls
      
    rescue URI::InvalidURIError => e
      Rails.logger.error "Invalid starting URL: #{starting_url} - #{e.message}"
      []
    end
  end

  def filter_same_domain_urls(urls, starting_url)
    return [] if urls.empty?
    
    begin
      starting_uri = URI.parse(starting_url)
      starting_domain = "#{starting_uri.scheme}://#{starting_uri.host}#{starting_uri.port != starting_uri.default_port ? ":#{starting_uri.port}" : ""}"
      
      Rails.logger.debug "Filtering #{urls.length} URLs for same domain: #{starting_domain}"
      
      # Optimized filtering - just check if URL starts with domain (much faster than URI parsing each)
      filtered_urls = urls.select { |url| url.start_with?(starting_domain) }
      
      Rails.logger.debug "Domain filtering result: #{filtered_urls.length} URLs"
      filtered_urls
      
    rescue URI::InvalidURIError => e
      Rails.logger.error "Invalid starting URL: #{starting_url} - #{e.message}"
      []
    end
  end

  def get_cached_sitemap(cache_key)
    return nil unless redis_available?
    
    begin
      $redis.get(cache_key)
    rescue Redis::BaseError => e
      Rails.logger.warn "Redis error getting cached sitemap: #{e.message}"
      nil
    end
  end

  def cache_sitemap(cache_key, content)
    return unless redis_available?
    
    begin
      $redis.setex(cache_key, SITEMAP_CACHE_TTL, content)
      Rails.logger.debug "Cached sitemap with key: #{cache_key}"
    rescue Redis::BaseError => e
      Rails.logger.warn "Redis error caching sitemap: #{e.message}"
    end
  end

  def redis_available?
    defined?($redis) && $redis.respond_to?(:get)
  rescue
    false
  end

  def path_similarity_bonus?(url_path, starting_path)
    # Extract category/section from starting path
    starting_category = extract_category(starting_path)
    return false if starting_category.nil? || starting_category.empty?
    
    # Check if URL path contains the same category
    url_path.downcase.include?(starting_category.downcase)
  end

  def extract_category(path)
    # Extract the first meaningful path segment
    # e.g., "/products/shoes/nike" -> "products"
    # e.g., "/blog/tech/ai" -> "blog"
    segments = path.split('/').reject(&:empty?)
    return nil if segments.empty?
    
    # Skip common root segments that aren't meaningful categories
    common_prefixes = %w[www api v1 v2 en us fr de es it ja zh]
    
    segments.each do |segment|
      unless common_prefixes.include?(segment.downcase)
        return segment
      end
    end
    
    # If all segments are common prefixes, return nil
    nil
  end

  def utility_page?(path)
    # Check if path matches common utility page patterns
    utility_patterns = [
      /\/(privacy|terms|legal|sitemap|robots|contact|about-us|disclaimer|cookie)/i,
      /\/(login|register|signin|signup|logout)/i,
      /\/(search|404|error|maintenance)/i,
      /\/(admin|dashboard|account|profile)/i,
      /\/(xml|rss|atom|feed)/i
    ]
    
    utility_patterns.any? { |pattern| path.match?(pattern) }
  end

  def current_memory_usage
    # Get current memory usage in MB
    # Uses RSS (Resident Set Size) which is the amount of memory currently in physical RAM
    begin
      if defined?(GC) && GC.respond_to?(:stat)
        # Try to get Ruby memory stats first (more accurate for Ruby memory usage)
        gc_stat = GC.stat
        total_allocated = gc_stat[:total_allocated_objects] || 0
        
        # Rough estimate: each object takes about 40 bytes on average
        estimated_mb = (total_allocated * 40.0) / (1024 * 1024)
        return estimated_mb
      end
    rescue StandardError => e
      Rails.logger.debug "Could not get GC memory stats: #{e.message}"
    end
    
    begin
      # Fall back to system memory usage via /proc (Linux/Mac)
      if File.exist?('/proc/self/status')
        status = File.read('/proc/self/status')
        if status =~ /VmRSS:\s*(\d+) kB/
          return $1.to_f / 1024.0 # Convert KB to MB
        end
      end
    rescue StandardError => e
      Rails.logger.debug "Could not read /proc/self/status: #{e.message}"
    end
    
    # Final fallback - return 0 if we can't measure memory
    0.0
  end
end