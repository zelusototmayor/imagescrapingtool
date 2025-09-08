require 'playwright'

class ImageScraper
  MAX_IMAGES = ENV.fetch('MAX_IMAGES', 200).to_i
  MAX_IMAGE_SIZE = 20.megabytes
  USER_AGENT = ENV.fetch('USER_AGENT', 'ImageSweepBot/0.1 (contact: support@imagesweep.app)')
  
  # Page limits to prevent infinite loops
  SUBPATH_MAX_PAGES = 25
  ENTIRE_WEBSITE_MAX_PAGES = 50

  def initialize(job)
    @job = job
    @visited_urls = Set.new
    @page_queue = []
    @images = []
    @pages_crawled = 0
    @origin = UrlValidator.new(@job.url).origin
  end

  def scrape
    FileUtils.mkdir_p(images_dir)
    
    case @job.scrape_mode
    when 'current_page'
      scrape_current_page_only
    when 'subpath_only'
      scrape_with_subpath_restriction
    when 'entire_website'
      scrape_entire_website
    else
      # Default to current page if somehow invalid
      scrape_current_page_only
    end
  end

  private

  def scrape_current_page_only
    scrape_page(@job.url)
    @pages_crawled = 1
    
    finalize_results
  end

  def scrape_with_subpath_restriction
    @page_queue << @job.url
    
    while @page_queue.any? && @images.length < MAX_IMAGES && @pages_crawled < SUBPATH_MAX_PAGES
      url = @page_queue.shift
      next if @visited_urls.include?(url)
      
      scrape_page(url)
      @pages_crawled += 1
      
      # Update progress - use dynamic calculation since we don't know total pages
      progress = [10 + (@pages_crawled * 5), 80].min
      @job.update!(progress: progress)
    end

    finalize_results
  end

  def scrape_entire_website
    @page_queue << @job.url
    
    while @page_queue.any? && @images.length < MAX_IMAGES && @pages_crawled < ENTIRE_WEBSITE_MAX_PAGES
      url = @page_queue.shift
      next if @visited_urls.include?(url)
      
      scrape_page(url)
      @pages_crawled += 1
      
      # Update progress - use dynamic calculation since we don't know total pages
      progress = [10 + (@pages_crawled * 3), 80].min
      @job.update!(progress: progress)
    end

    finalize_results
  end

  def finalize_results
    # Always set progress to 90% when scraping is complete
    @job.update!(progress: 90)
    
    images_included = [@images.length, MAX_IMAGES].min
    truncated = @images.length > MAX_IMAGES

    if truncated
      @images = @images.first(MAX_IMAGES)
    end

    {
      pages_crawled: @pages_crawled,
      images_total: @images.length + (truncated ? (@images.length - MAX_IMAGES) : 0),
      images_included: images_included,
      images: @images,
      truncated: truncated
    }
  end

  def scrape_page(url)
    @visited_urls << url
    
    Rails.logger.info "Scraping page: #{url}"
    
    if @job.render_js
      begin
        scrape_with_playwright(url)
        Rails.logger.info "Successfully scraped #{url} with Playwright"
      rescue => e
        Rails.logger.warn "Playwright failed for #{url}: #{e.message}. Attempting HTTP fallback..."
        begin
          scrape_with_http(url)
          Rails.logger.info "Successfully scraped #{url} with HTTP fallback"
        rescue => http_error
          Rails.logger.error "Both Playwright and HTTP failed for #{url}. Playwright: #{e.message}, HTTP: #{http_error.message}"
        end
      end
    else
      begin
        scrape_with_http(url)
        Rails.logger.info "Successfully scraped #{url} with HTTP"
      rescue => e
        Rails.logger.error "HTTP scraping failed for #{url}: #{e.message}"
      end
    end
  rescue => e
    Rails.logger.error "Unexpected error scraping #{url}: #{e.message}"
  end

  def scrape_with_playwright(url)
    Rails.logger.info "Starting Playwright scraping for #{url}"
    
    playwright = nil
    browser = nil
    page = nil
    
    begin
      # Use Timeout to prevent hanging on Playwright operations
      Timeout.timeout(90) do # Increased to 90 seconds for better reliability
        Rails.logger.info "Creating Playwright instance..."
        
        # Create Playwright instance with CLI path parameter
        playwright = Playwright.create(playwright_cli_executable_path: 'npx playwright')
        Rails.logger.info "Playwright instance created, launching Chromium..."
        
        # Launch browser with more conservative settings
        browser = playwright.chromium.launch(
          headless: true,
          timeout: 45000, # 45 second timeout for browser launch
          args: [
            '--no-sandbox',
            '--disable-dev-shm-usage',
            '--disable-gpu',
            '--disable-web-security',
            '--disable-features=VizDisplayCompositor',
            '--memory-pressure-off'
          ]
        )
        Rails.logger.info "Browser launched, creating new page..."
        
        page = browser.new_page
        
        # Set page timeouts
        page.set_default_timeout(45000) # 45 seconds
        page.set_default_navigation_timeout(45000) # 45 seconds
        
        Rails.logger.info "Navigating to #{url} with networkidle wait..."
        begin
          page.goto(url, waitUntil: 'networkidle', timeout: 45000)
          Rails.logger.info "Page loaded successfully for #{url}"
        rescue => nav_error
          Rails.logger.warn "Navigation with networkidle failed, trying domcontentloaded: #{nav_error.message}"
          page.goto(url, waitUntil: 'domcontentloaded', timeout: 30000)
          Rails.logger.info "Page loaded with domcontentloaded for #{url}"
        end
        
        # Extract images from various sources
        Rails.logger.info "Extracting img tags for #{url}"
        extract_img_tags(page, url)
        Rails.logger.info "Extracting CSS backgrounds for #{url}"
        extract_css_backgrounds(page, url)
        Rails.logger.info "Extracting OG images for #{url}"
        extract_og_images(page, url)
        
        # Find additional pages to crawl (only for multi-page modes)
        if should_extract_links?
          Rails.logger.info "Extracting links for #{url}"
          extract_links(page, url)
        end
        Rails.logger.info "Playwright scraping completed for #{url}"
      end
    rescue Timeout::Error => e
      Rails.logger.error "Playwright operation timed out for #{url}: #{e.message}"
      cleanup_browser_processes
      raise e
    rescue => e
      Rails.logger.error "Error in scrape_with_playwright: #{e.class.name}: #{e.message}"
      Rails.logger.error "Backtrace: #{e.backtrace.first(5).join('\n')}"
      cleanup_browser_processes
      raise e
    ensure
      # Explicit cleanup in reverse order
      begin
        page&.close if page && !page.closed?
        Rails.logger.debug "Page closed for #{url}"
      rescue => e
        Rails.logger.warn "Error closing page: #{e.message}"
      end
      
      begin
        browser&.close if browser && browser.connected?
        Rails.logger.debug "Browser closed for #{url}"
      rescue => e
        Rails.logger.warn "Error closing browser: #{e.message}"
      end
      
      begin
        playwright&.stop if playwright
        Rails.logger.debug "Playwright stopped for #{url}"
      rescue => e
        Rails.logger.warn "Error stopping playwright: #{e.message}"
      end
      
      # Final process cleanup as safety net
      cleanup_browser_processes
    end
  end

  def scrape_with_http(url)
    response = Faraday.get(url) do |req|
      req.headers['User-Agent'] = USER_AGENT
      req.options.timeout = 30
    end
    
    return unless response.success?
    
    doc = Nokogiri::HTML(response.body)
    
    # Extract images from various sources  
    extract_img_tags_nokogiri(doc, url)
    extract_og_images_nokogiri(doc, url)
    
    # Find additional pages to crawl (only for multi-page modes)
    if should_extract_links?
      extract_links_nokogiri(doc, url)
    end
  end

  def extract_img_tags(page, page_url)
    page.query_selector_all('img').each do |img|
      src = img.get_attribute('src')
      next unless src
      
      srcset = img.get_attribute('srcset')
      alt = img.get_attribute('alt')
      classes = img.get_attribute('class')
      id = img.get_attribute('id')
      
      # Process main src
      process_image_url(src, page_url, {
        tag: 'img',
        alt: alt,
        classes: classes&.split(' ') || [],
        id: id,
        position_y: get_element_position_y(img)
      })
      
      # Process srcset candidates
      if srcset
        parse_srcset(srcset).each do |candidate_src|
          process_image_url(candidate_src, page_url, {
            tag: 'img',
            alt: alt,
            classes: classes&.split(' ') || [],
            id: id,
            position_y: get_element_position_y(img)
          })
        end
      end
    end
    
    # Process source elements
    page.query_selector_all('source').each do |source|
      srcset = source.get_attribute('srcset')
      next unless srcset
      
      parse_srcset(srcset).each do |src|
        process_image_url(src, page_url, {
          tag: 'source',
          classes: [],
          position_y: 0
        })
      end
    end
  end

  def extract_img_tags_nokogiri(doc, page_url)
    doc.css('img').each do |img|
      src = img['src']
      next unless src
      
      process_image_url(src, page_url, {
        tag: 'img',
        alt: img['alt'],
        classes: (img['class'] || '').split(' '),
        id: img['id'],
        position_y: 0
      })
      
      # Process srcset
      if img['srcset']
        parse_srcset(img['srcset']).each do |candidate_src|
          process_image_url(candidate_src, page_url, {
            tag: 'img',
            alt: img['alt'],
            classes: (img['class'] || '').split(' '),
            id: img['id'],
            position_y: 0
          })
        end
      end
    end
    
    doc.css('source').each do |source|
      next unless source['srcset']
      
      parse_srcset(source['srcset']).each do |src|
        process_image_url(src, page_url, {
          tag: 'source',
          classes: [],
          position_y: 0
        })
      end
    end
  end

  def extract_css_backgrounds(page, page_url)
    # This is complex and requires parsing computed styles
    # For now, we'll skip this in the MVP
  end

  def extract_og_images(page, page_url)
    page.query_selector_all('meta[property="og:image"]').each do |meta|
      content = meta.get_attribute('content')
      next unless content
      
      process_image_url(content, page_url, {
        tag: 'meta',
        classes: [],
        position_y: 0
      })
    end
  end

  def extract_og_images_nokogiri(doc, page_url)
    doc.css('meta[property="og:image"]').each do |meta|
      content = meta['content']
      next unless content
      
      process_image_url(content, page_url, {
        tag: 'meta',
        classes: [],
        position_y: 0
      })
    end
  end

  def extract_links(page, page_url)
    page.query_selector_all('a[href]').each do |link|
      href = link.get_attribute('href')
      next unless href
      
      absolute_url = make_absolute_url(href, page_url)
      next unless should_crawl_url?(absolute_url, page_url)
      
      @page_queue << absolute_url unless @visited_urls.include?(absolute_url)
    end
  end

  def extract_links_nokogiri(doc, page_url)
    doc.css('a[href]').each do |link|
      href = link['href']
      next unless href
      
      absolute_url = make_absolute_url(href, page_url)
      next unless should_crawl_url?(absolute_url, page_url)
      
      @page_queue << absolute_url unless @visited_urls.include?(absolute_url)
    end
  end

  def process_image_url(src, page_url, dom_context)
    return if @images.length >= MAX_IMAGES
    return unless src && !src.start_with?('data:')
    
    absolute_url = make_absolute_url(src, page_url)
    return unless absolute_url && valid_image_url?(absolute_url)
    
    # Dedupe by URL
    return if @images.any? { |img| img[:source_url] == absolute_url }
    
    # Download and process the image
    download_image(absolute_url, page_url, dom_context)
  end

  def download_image(url, found_on_url, dom_context)
    Rails.logger.info "Downloading image #{@images.length + 1}: #{url}"
    
    # Update progress more frequently during downloads
    if @images.length > 0 && @images.length % 2 == 0
      progress = [20 + (@images.length * 15), 85].min
      @job.update!(progress: progress, message: "Downloaded #{@images.length} images...")
      Rails.logger.info "Updated progress to #{progress}% (#{@images.length} images downloaded)"
    end
    
    # Use overall timeout to prevent hanging on image downloads
    Timeout.timeout(45) do # 45 second max per image
      # First try HEAD to check content type and size
      head_response = Faraday.head(url) do |req|
        req.headers['User-Agent'] = USER_AGENT
        req.options.timeout = 10
        req.options.open_timeout = 5
      end
      
      if head_response.success?
        content_type = head_response.headers['content-type']
        content_length = head_response.headers['content-length']&.to_i
        
        return unless content_type&.start_with?('image/')
        return if content_length && content_length > MAX_IMAGE_SIZE
        Rails.logger.debug "HEAD check passed for #{url}, content-type: #{content_type}"
      else
        Rails.logger.debug "HEAD request failed for #{url}, proceeding with GET"
      end
      
      # Download the image
      response = Faraday.get(url) do |req|
        req.headers['User-Agent'] = USER_AGENT
        req.options.timeout = 30
        req.options.open_timeout = 5
      end
      
      return unless response.success?
      return unless response.headers['content-type']&.start_with?('image/')
      return if response.body.bytesize > MAX_IMAGE_SIZE
      
      Rails.logger.debug "Successfully downloaded #{url}, size: #{response.body.bytesize} bytes"
      
      # Get image metadata
      image_info = FastImage.new(StringIO.new(response.body))
      return unless image_info.size
      
      width, height = image_info.size
      mime_type = response.headers['content-type']
      
      # Classify the image
      category = classify_image(url, found_on_url, dom_context, width, height)
      
      # Generate filename
      rank = @images.count { |img| img[:category] == category } + 1
      filename = generate_filename(category, rank, url, dom_context, mime_type)
      
      # Save the image
      image_path = File.join(images_dir, filename)
      FileUtils.mkdir_p(File.dirname(image_path))
      File.write(image_path, response.body, mode: 'wb')
      
      # Store image metadata
      @images << {
        filename: filename,
        source_url: url,
        found_on: found_on_url,
        category: category,
        width: width,
        height: height,
        mime: mime_type,
        dom_context: dom_context
      }
      
      Rails.logger.info "✓ Successfully downloaded #{filename} (#{width}x#{height}) - Total: #{@images.length} images"
      
      # Update progress after each successful download
      progress = [20 + (@images.length * 15), 85].min
      @job.update!(progress: progress, message: "Downloaded #{@images.length} images...")
      Rails.logger.info "Updated job progress to #{progress}%"
    end
  rescue Timeout::Error => e
    Rails.logger.warn "Image download timed out for #{url}: #{e.message}"
  rescue => e
    Rails.logger.warn "Failed to download image #{url}: #{e.message}"
  end

  def classify_image(url, found_on_url, dom_context, width, height)
    # Hero: large images or from og:image
    if dom_context[:tag] == 'meta' || 
       width >= 1000 || 
       (width > 0 && height > 0 && (width.to_f / height) >= 2.0) ||
       (dom_context[:position_y] && dom_context[:position_y] <= 1200)
      return 'hero'
    end
    
    # Logo/Icon: small images or matching patterns
    if (width <= 128 && height <= 128) ||
       url.match?(/(logo|icon)/i) ||
       dom_context[:alt]&.match?(/(logo|icon)/i) ||
       dom_context[:classes]&.any? { |cls| cls.match?(/(logo|icon)/i) } ||
       dom_context[:id]&.match?(/(logo|icon)/i)
      return 'logo'
    end
    
    # Product: from product pages or matching patterns
    if found_on_url.match?(/(product|shop|item|cart)/i) ||
       dom_context[:alt]&.match?(/(product|shop|item|cart)/i) ||
       dom_context[:classes]&.any? { |cls| cls.match?(/(product|shop|item|cart)/i) } ||
       dom_context[:id]&.match?(/(product|shop|item|cart)/i)
      return 'product'
    end
    
    'other'
  end

  def generate_filename(category, rank, url, dom_context, mime_type)
    # Get file extension
    ext = case mime_type
          when /jpeg/ then 'jpg'
          when /png/ then 'png'
          when /gif/ then 'gif'
          when /webp/ then 'webp'
          when /svg/ then 'svg'
          else 'jpg'
          end
    
    # Create slug from URL or alt text
    slug = if dom_context[:alt] && !dom_context[:alt].empty?
             slugify(dom_context[:alt])
           else
             slugify(File.basename(URI.parse(url).path, '.*'))
           end
    
    slug = 'image' if slug.empty?
    slug = slug[0..50] # Limit length
    
    "#{category}/#{'%03d' % rank}_#{slug}.#{ext}"
  end

  def slugify(text)
    text.to_s
        .downcase
        .gsub(/[^\w\s-]/, '')
        .gsub(/\s+/, '-')
        .gsub(/-+/, '-')
        .gsub(/^-|-$/, '')
  end

  def make_absolute_url(url, base_url)
    return nil if url.nil? || url.empty?
    return url if url.start_with?('http')
    
    base_uri = URI.parse(base_url)
    URI.join(base_uri, url).to_s
  rescue URI::InvalidURIError
    nil
  end

  def valid_image_url?(url)
    uri = URI.parse(url)
    uri.scheme && uri.host
  rescue URI::InvalidURIError
    false
  end

  def should_extract_links?
    @job.scrape_mode != 'current_page'
  end

  def should_crawl_url?(url, current_page_url)
    return false unless url
    
    uri = URI.parse(url)
    current_uri = URI.parse(current_page_url)
    
    # Same origin check
    return false unless uri.scheme == current_uri.scheme && uri.host == current_uri.host && uri.port == current_uri.port
    
    # Apply restrictions based on scrape mode
    case @job.scrape_mode
    when 'current_page'
      # This shouldn't be called for current_page mode, but just in case
      return false
    when 'subpath_only'
      # Subpath restriction - only crawl within the original URL's path
      initial_uri = URI.parse(@job.url)
      return false unless uri.path.start_with?(initial_uri.path)
    when 'entire_website'
      # No additional restrictions - can crawl anywhere on the same domain
      true
    else
      false
    end
    
    true
  rescue URI::InvalidURIError
    false
  end

  def parse_srcset(srcset)
    srcset.split(',').map do |candidate|
      url = candidate.strip.split(' ').first
      # Skip invalid URL fragments that don't look like URLs
      next if url.nil? || url.empty?
      next if url.match?(/^\d+[wx]$/) # Skip width/pixel density descriptors like "2x" or "800w"
      next if url.match?(/^(al_c|h_\d+|w_\d+|usm_|enc_|quality_)/) # Skip URL parameters that got split incorrectly
      url
    end.compact.select do |url|
      # Additional validation - must look like a URL
      url.match?(/^https?:\/\//) || url.start_with?('/') || url.start_with?('./')
    end
  end

  def get_element_position_y(element)
    # This would require evaluating JavaScript to get scroll position
    # For MVP, we'll return 0
    0
  end


  def images_dir
    File.join(@job.artifact_dir, 'images')
  end

  private

  def cleanup_browser_processes
    begin
      # Kill any orphaned Chromium processes
      system('pkill -f "chromium.*--headless" >/dev/null 2>&1')
      system('pkill -f "chrome.*--headless" >/dev/null 2>&1')
      Rails.logger.debug "Cleaned up orphaned browser processes"
    rescue => e
      Rails.logger.warn "Error during browser process cleanup: #{e.message}"
    end
  end
end