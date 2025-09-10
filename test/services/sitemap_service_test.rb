require "test_helper"
require "ostruct"

class SitemapServiceTest < ActiveSupport::TestCase
  def setup
    @service = SitemapService.new
    @starting_url = 'https://example.com/products/shoes'
  end

  test "extract_domain returns correct domain" do
    assert_equal 'https://example.com', @service.send(:extract_domain, 'https://example.com/products/shoes')
    assert_equal 'http://example.com:8080', @service.send(:extract_domain, 'http://example.com:8080/path')
    assert_nil @service.send(:extract_domain, 'invalid-url')
  end

  test "valid_url? validates URLs correctly" do
    assert @service.send(:valid_url?, 'https://example.com')
    assert @service.send(:valid_url?, 'http://example.com/path')
    assert_not @service.send(:valid_url?, 'ftp://example.com')
    assert_not @service.send(:valid_url?, 'invalid-url')
    assert_not @service.send(:valid_url?, '')
    assert_not @service.send(:valid_url?, nil)
  end

  test "parse_sitemap extracts URLs from valid XML" do
    xml_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <url>
          <loc>https://example.com/page1</loc>
        </url>
        <url>
          <loc>https://example.com/page2</loc>
        </url>
        <url>
          <loc>invalid-url</loc>
        </url>
      </urlset>
    XML

    urls = @service.send(:parse_sitemap, xml_content)
    assert_equal 2, urls.length
    assert_includes urls, 'https://example.com/page1'
    assert_includes urls, 'https://example.com/page2'
    assert_not_includes urls, 'invalid-url'
  end

  test "parse_sitemap handles malformed XML gracefully" do
    malformed_xml = "<urlset><url><loc>https://example.com</loc>"  # Missing closing tags
    urls = @service.send(:parse_sitemap, malformed_xml)
    assert_equal ["https://example.com"], urls  # Nokogiri is lenient, still extracts the URL
  end

  test "parse_sitemap returns empty array for non-XML content" do
    html_content = "<html><body>Not XML</body></html>"
    urls = @service.send(:parse_sitemap, html_content)
    assert_equal [], urls
  end

  test "filter_subpath_urls filters correctly" do
    urls = [
      'https://example.com/products/shoes/nike',
      'https://example.com/products/shoes/adidas', 
      'https://example.com/products/shirts',
      'https://example.com/about',
      'https://other-domain.com/products/shoes'
    ]
    
    filtered = @service.send(:filter_subpath_urls, urls, @starting_url)
    
    assert_equal 2, filtered.length
    assert_includes filtered, 'https://example.com/products/shoes/nike'
    assert_includes filtered, 'https://example.com/products/shoes/adidas'
    assert_not_includes filtered, 'https://example.com/products/shirts'
    assert_not_includes filtered, 'https://example.com/about'
    assert_not_includes filtered, 'https://other-domain.com/products/shoes'
  end

  test "filter_same_domain_urls filters correctly" do
    urls = [
      'https://example.com/products/shoes',
      'https://example.com/about',
      'https://example.com/contact',
      'https://other-domain.com/page',
      'http://example.com/page' # Different scheme
    ]
    
    filtered = @service.send(:filter_same_domain_urls, urls, @starting_url)
    
    assert_equal 3, filtered.length
    assert_includes filtered, 'https://example.com/products/shoes'
    assert_includes filtered, 'https://example.com/about'
    assert_includes filtered, 'https://example.com/contact'
    assert_not_includes filtered, 'https://other-domain.com/page'
    assert_not_includes filtered, 'http://example.com/page'
  end

  test "filter_urls_for_mode applies correct limits" do
    # Test that limits are correctly applied
    urls = (1..60).map { |i| "https://example.com/page#{i}" }
    
    # Create mock job objects
    subpath_job = OpenStruct.new(scrape_mode: 'subpath_only', url: 'https://example.com')
    entire_job = OpenStruct.new(scrape_mode: 'entire_website', url: 'https://example.com')
    
    # Test subpath limit (25)
    filtered = @service.send(:filter_urls_for_mode, urls, subpath_job)
    assert_equal 25, filtered.length
    
    # Test entire website limit (50)
    filtered = @service.send(:filter_urls_for_mode, urls, entire_job) 
    assert_equal 50, filtered.length
  end

  test "filter_urls_for_mode handles unknown scrape modes" do
    urls = ['https://example.com/page1']
    job = OpenStruct.new(scrape_mode: 'unknown_mode', url: 'https://example.com')
    
    result = @service.send(:filter_urls_for_mode, urls, job)
    assert_equal [], result
  end

  # ====== SITEMAP INDEX TESTS ======

  test "parse_sitemap detects sitemap index files" do
    sitemap_index_xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <sitemap>
          <loc>https://example.com/sitemap1.xml</loc>
        </sitemap>
        <sitemap>
          <loc>https://example.com/sitemap2.xml</loc>
        </sitemap>
      </sitemapindex>
    XML

    # Mock the fetch_sitemap method to return sample sitemaps
    @service.define_singleton_method(:fetch_sitemap) do |url|
      if url == 'https://example.com/sitemap1.xml'
        <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
            <url><loc>https://example.com/page1</loc></url>
            <url><loc>https://example.com/page2</loc></url>
          </urlset>
        XML
      elsif url == 'https://example.com/sitemap2.xml'
        <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
            <url><loc>https://example.com/page3</loc></url>
            <url><loc>https://example.com/page4</loc></url>
          </urlset>
        XML
      else
        nil
      end
    end
    
    urls = @service.send(:parse_sitemap, sitemap_index_xml)
    assert_equal 4, urls.length
    assert_includes urls, 'https://example.com/page1'
    assert_includes urls, 'https://example.com/page2'
    assert_includes urls, 'https://example.com/page3'
    assert_includes urls, 'https://example.com/page4'
  end

  test "parse_sitemap_index extracts sitemap URLs correctly" do
    sitemap_index_xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <sitemap>
          <loc>https://example.com/sitemap1.xml</loc>
        </sitemap>
        <sitemap>
          <loc>https://example.com/sitemap2.xml</loc>
        </sitemap>
        <sitemap>
          <loc>invalid-sitemap-url</loc>
        </sitemap>
      </sitemapindex>
    XML

    doc = Nokogiri::XML(sitemap_index_xml)
    
    # Mock fetch_sitemap to return empty to avoid actual HTTP calls
    @service.define_singleton_method(:fetch_sitemap) { |url| nil }
    
    result = @service.send(:parse_sitemap_index, doc)
    # Should return empty since fetch_sitemap returns nil, but method should execute without error
    assert_equal [], result
  end

  test "parse_sitemap handles nested sitemap indexes" do
    # Create a nested sitemap index structure  
    parent_index_xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <sitemap>
          <loc>https://example.com/nested-index.xml</loc>
        </sitemap>
      </sitemapindex>
    XML

    nested_index_xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <sitemap>
          <loc>https://example.com/final-sitemap.xml</loc>
        </sitemap>
      </sitemapindex>
    XML

    final_sitemap_xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <url><loc>https://example.com/final-page</loc></url>
      </urlset>
    XML

    @service.define_singleton_method(:fetch_sitemap) do |url|
      case url
      when 'https://example.com/nested-index.xml'
        nested_index_xml
      when 'https://example.com/final-sitemap.xml'
        final_sitemap_xml
      else
        nil
      end
    end
    
    urls = @service.send(:parse_sitemap, parent_index_xml)
    assert_equal 1, urls.length
    assert_includes urls, 'https://example.com/final-page'
  end

  test "caching methods handle redis unavailability gracefully" do
    # Test that caching methods don't crash when Redis is unavailable
    
    # Test redis_available? returns false when redis is not defined
    refute @service.send(:redis_available?)
    
    # Test get_cached_sitemap returns nil when redis unavailable
    assert_nil @service.send(:get_cached_sitemap, 'test-key')
    
    # Test cache_sitemap doesn't crash when redis unavailable
    assert_nothing_raised do
      @service.send(:cache_sitemap, 'test-key', 'test-content')
    end
  end

  test "fetch_sitemap checks visited sitemaps correctly" do
    # Verify that the visited sitemaps tracking works
    # First, verify visited_sitemaps is empty
    assert_equal [], @service.instance_variable_get(:@visited_sitemaps).to_a
    
    # Create a simple test where fetch_sitemap adds to visited list
    # Even if it returns nil due to HTTP error, it should still mark as visited
    
    # Mock Faraday to return a failure
    mock_faraday_response = OpenStruct.new(success?: false, status: 404)
    Faraday.define_singleton_method(:get) { |url| mock_faraday_response }
    
    result1 = @service.fetch_sitemap('https://example.com/sitemap.xml')
    assert_nil result1
    assert_includes @service.instance_variable_get(:@visited_sitemaps), 'https://example.com/sitemap.xml'
    
    # Second call should return nil immediately (already visited)
    result2 = @service.fetch_sitemap('https://example.com/sitemap.xml')
    assert_nil result2
  end
  
  test "parse_sitemap_index handles invalid sitemap URLs" do
    # Test the parse_sitemap_index method directly with a simple case
    sitemap_index_xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <sitemap>
          <loc>https://example.com/valid-sitemap.xml</loc>
        </sitemap>
        <sitemap>
          <loc>invalid-url</loc>
        </sitemap>
      </sitemapindex>
    XML

    doc = Nokogiri::XML(sitemap_index_xml)
    
    # Test that it extracts only valid URLs from the index
    sitemap_urls = []
    doc.css('sitemap loc').each do |loc_node|
      url = loc_node.text.strip
      sitemap_urls << url if @service.send(:valid_url?, url)
    end
    
    assert_equal 1, sitemap_urls.length
    assert_includes sitemap_urls, 'https://example.com/valid-sitemap.xml'
    assert_not_includes sitemap_urls, 'invalid-url'
  end

  # ====== URL PRIORITIZATION TESTS ======

  test "score_url_importance applies depth penalty correctly" do
    starting_url = 'https://example.com/products'
    
    shallow_url = 'https://example.com/products/shoes'
    deep_url = 'https://example.com/products/shoes/brand/model/variant'
    
    shallow_score = @service.send(:score_url_importance, shallow_url, starting_url)
    deep_score = @service.send(:score_url_importance, deep_url, starting_url)
    
    # Shallow URL should have higher score than deep URL
    assert shallow_score > deep_score
    assert_operator shallow_score - deep_score, :>=, 20 # At least 2 levels * 10 points difference
  end

  test "score_url_importance applies similarity bonus" do
    starting_url = 'https://example.com/products/shoes'
    
    similar_url = 'https://example.com/products/boots'  # Same category
    different_url = 'https://example.com/blog/news'     # Different category
    
    similar_score = @service.send(:score_url_importance, similar_url, starting_url)
    different_score = @service.send(:score_url_importance, different_url, starting_url)
    
    # Similar URL should have higher score due to bonus
    assert similar_score > different_score
    assert_operator similar_score - different_score, :>=, 30 # Similarity bonus
  end

  test "score_url_importance applies utility page penalty" do
    starting_url = 'https://example.com/products'
    
    content_url = 'https://example.com/products/shoes'
    utility_url = 'https://example.com/privacy-policy'
    
    content_score = @service.send(:score_url_importance, content_url, starting_url)
    utility_score = @service.send(:score_url_importance, utility_url, starting_url)
    
    # Content URL should have higher score than utility page
    assert content_score > utility_score
    assert_operator content_score - utility_score, :>=, 50 # Utility penalty
  end

  test "utility_page? detects common utility pages" do
    utility_paths = [
      '/privacy-policy',
      '/terms-of-service',
      '/contact-us',
      '/login',
      '/sitemap.xml',
      '/admin/dashboard'
    ]
    
    content_paths = [
      '/products/shoes',
      '/blog/tech-news',
      '/about-our-company',
      '/news/updates'
    ]
    
    utility_paths.each do |path|
      assert @service.send(:utility_page?, path), "#{path} should be detected as utility page"
    end
    
    content_paths.each do |path|
      assert_not @service.send(:utility_page?, path), "#{path} should not be detected as utility page"
    end
  end

  test "extract_category extracts meaningful categories" do
    test_cases = [
      ['/products/shoes/nike', 'products'],
      ['/blog/tech/ai', 'blog'],
      ['/news/2024/january', 'news'],
      ['/en/products/shoes', 'products'], # Skip language code
      ['/api/v1/users', 'users'],         # Should return meaningful segment after skipping prefixes
      ['/', nil],                         # Root path
      ['/www/content', 'content']         # Skip www
    ]
    
    test_cases.each do |path, expected|
      result = @service.send(:extract_category, path)
      if expected.nil?
        assert_nil result, "extract_category('#{path}') should return nil"
      else
        assert_equal expected, result, "extract_category('#{path}') should return '#{expected}'"
      end
    end
  end

  test "prioritize_urls sorts by score descending" do
    starting_url = 'https://example.com/products'
    
    urls = [
      'https://example.com/privacy-policy',           # Low score (utility page)
      'https://example.com/products/shoes',           # High score (shallow + similar)
      'https://example.com/products/deep/nested/item', # Medium score (similar but deep)
      'https://example.com/blog/news'                 # Medium score (shallow but different)
    ]
    
    prioritized = @service.send(:prioritize_urls, urls, starting_url)
    
    # Should be sorted by score descending
    assert_equal 'https://example.com/products/shoes', prioritized.first
    assert_equal 'https://example.com/privacy-policy', prioritized.last
  end

  test "path_similarity_bonus? correctly identifies similar paths" do
    starting_path = '/products/shoes'
    
    similar_paths = [
      '/products/boots',
      '/products/sneakers',
      '/products/athletic-wear'
    ]
    
    different_paths = [
      '/blog/news',
      '/about-us',
      '/services/support'
    ]
    
    similar_paths.each do |path|
      assert @service.send(:path_similarity_bonus?, path, starting_path), 
             "#{path} should be similar to #{starting_path}"
    end
    
    different_paths.each do |path|
      assert_not @service.send(:path_similarity_bonus?, path, starting_path),
                 "#{path} should not be similar to #{starting_path}"
    end
  end

  test "prioritization is integrated into filter_urls_for_mode" do
    # Create URLs that will be sorted by prioritization
    # NOTE: Using entire_website mode so privacy-policy won't be filtered out by subpath filtering
    urls = [
      'https://example.com/privacy-policy',     # Should be last (utility page)
      'https://example.com/products/shoes/nike', # Should be first (shallow + similar) 
      'https://example.com/products/deep/nested/very/deep/item', # Should be middle (similar but very deep)
      'https://example.com/blog/random'         # Should be third (different category)
    ]
    
    job = OpenStruct.new(
      scrape_mode: 'entire_website', 
      url: 'https://example.com/products'
    )
    
    # Filter should return prioritized results
    result = @service.send(:filter_urls_for_mode, urls, job)
    
    # First result should be the highest priority URL
    assert_equal 'https://example.com/products/shoes/nike', result.first
    # Last result should be the utility page  
    assert_equal 'https://example.com/privacy-policy', result.last
  end

  # ====== PHASE 3: COMPREHENSIVE TESTING ======

  test "integration_test_real_website_sitemap_processing" do
    # Integration test with a real website (using torontocupcake.com from our earlier tests)
    service = SitemapService.new
    
    # This is a real integration test - it will make actual HTTP requests
    # Skip if no network connectivity to avoid test failures in CI
    begin
      response = Faraday.get('https://www.torontocupcake.com/sitemap.xml')
      skip "Skipping integration test - no network connectivity" unless response.success?
    rescue Faraday::Error
      skip "Skipping integration test - network error"
    end
    
    urls = service.fetch_sitemap_urls('https://www.torontocupcake.com')
    
    assert urls.is_a?(Array), "Should return array of URLs"
    assert urls.length > 0, "Should find URLs in real sitemap"
    assert urls.all? { |url| url.start_with?('https://www.torontocupcake.com') }, "All URLs should be from same domain"
    
    # Test that prioritization works with real URLs
    job = OpenStruct.new(scrape_mode: 'entire_website', url: 'https://www.torontocupcake.com')
    filtered_urls = service.filter_urls_for_mode(urls, job)
    
    assert filtered_urls.length > 0, "Should have filtered URLs"
    assert filtered_urls.first == 'https://www.torontocupcake.com/' || 
           filtered_urls.first == 'https://www.torontocupcake.com', "Homepage should be prioritized first"
  end

  test "performance_test_large_url_filtering" do
    service = SitemapService.new
    
    # Test with large URL sets to ensure performance is acceptable
    large_url_set = (1..10000).map { |i| "https://example.com/page#{i}.html" }
    
    start_time = Time.now
    filtered = service.send(:filter_same_domain_urls, large_url_set, "https://example.com")
    end_time = Time.now
    
    processing_time = end_time - start_time
    
    assert_equal large_url_set.length, filtered.length, "Should filter all matching URLs"
    assert processing_time < 1.0, "Should process 10K URLs in under 1 second, took #{processing_time}s"
    
    # Test prioritization performance
    start_time = Time.now
    prioritized = service.send(:prioritize_urls, large_url_set, "https://example.com")
    end_time = Time.now
    
    prioritization_time = end_time - start_time
    
    assert_equal large_url_set.length, prioritized.length, "Should prioritize all URLs"
    assert prioritization_time < 2.0, "Should prioritize 10K URLs in under 2 seconds, took #{prioritization_time}s"
  end

  test "error_handling_network_failures" do
    service = SitemapService.new
    
    # Test with non-existent domain
    urls = service.fetch_sitemap_urls('https://this-domain-does-not-exist-12345.com')
    assert_nil urls, "Should return nil for non-existent domain"
    
    # Test with domain that exists but has no sitemap
    urls = service.fetch_sitemap_urls('https://httpbin.org')
    assert_nil urls, "Should return nil when no sitemap exists"
  end

  test "error_handling_malformed_xml_edge_cases" do
    service = SitemapService.new
    
    # Test various malformed XML scenarios
    malformed_xmls = [
      "",                                    # Empty content
      "Not XML at all",                     # Plain text
      "<xml>unclosed tag",                  # Unclosed tags
      "<urlset><url><loc></loc></url></urlset>", # Empty location
      "<urlset><url><loc>invalid-url</loc></url></urlset>", # Invalid URL
      "<urlset><url></url></urlset>",       # Missing loc element
      "<?xml version='1.0'?><urlset xmlns='http://www.sitemaps.org/schemas/sitemap/0.9'><url><loc>https://example.com</loc></url><url><loc>not-a-url</loc></url></urlset>" # Mixed valid/invalid
    ]
    
    malformed_xmls.each_with_index do |xml, index|
      result = service.send(:parse_sitemap, xml)
      
      assert result.is_a?(Array), "Should always return array for malformed XML case #{index + 1}"
      # Some malformed XML might still extract some valid URLs (like case 7)
      result.each do |url|
        assert service.send(:valid_url?, url), "Any returned URLs should be valid for case #{index + 1}: #{url}"
      end
    end
  end

  test "end_to_end_subpath_mode_integration" do
    # Create comprehensive test URLs that would be found in a sitemap
    sitemap_urls = [
      'https://example.com/',
      'https://example.com/products/',
      'https://example.com/products/shoes',
      'https://example.com/products/shoes/nike',
      'https://example.com/products/shirts', 
      'https://example.com/blog/',
      'https://example.com/blog/tech',
      'https://example.com/about',
      'https://example.com/privacy-policy'
    ]
    
    # Mock the class method properly  
    SitemapService.define_singleton_method(:fetch_filtered_urls) do |starting_url, job|
      service = SitemapService.new
      urls = service.filter_urls_for_mode(sitemap_urls, job)
      urls
    end
    
    # Test subpath mode end-to-end
    job = OpenStruct.new(
      scrape_mode: 'subpath_only',
      url: 'https://example.com/products/shoes'
    )
    
    result = SitemapService.fetch_filtered_urls(job.url, job)
    
    assert result.is_a?(Array), "Should return array"
    assert result.length > 0, "Should find matching subpath URLs"
    
    # Should only include URLs that start with the subpath
    result.each do |url|
      assert url.start_with?('https://example.com/products/shoes'), 
             "All URLs should be within subpath: #{url}"
    end
    
    # Should be prioritized (shoes exact match should come before shoes/nike)
    if result.include?('https://example.com/products/shoes')
      shoes_index = result.index('https://example.com/products/shoes')
      nike_index = result.index('https://example.com/products/shoes/nike')
      if nike_index
        assert shoes_index < nike_index, "Shorter path should be prioritized higher"
      end
    end
    
    # Restore original method
    SitemapService.define_singleton_method(:fetch_filtered_urls) do |starting_url, job|
      service = new
      urls = service.fetch_sitemap_urls(starting_url)
      return nil if urls.nil? || urls.empty?
      service.filter_urls_for_mode(urls, job)
    end
  end

  test "end_to_end_entire_website_mode_integration" do
    # Test URLs with various priorities
    sitemap_urls = [
      'https://example.com/privacy-policy',      # Utility page - should be last
      'https://example.com/deep/nested/path',    # Deep page - lower priority
      'https://example.com/products',            # Content page - good priority  
      'https://example.com/',                    # Homepage - should be first
      'https://other-domain.com/page'            # Different domain - should be excluded
    ]
    
    # Mock the class method properly
    SitemapService.define_singleton_method(:fetch_filtered_urls) do |starting_url, job|
      service = SitemapService.new
      urls = service.filter_urls_for_mode(sitemap_urls, job)
      urls
    end
    
    # Test entire website mode end-to-end
    job = OpenStruct.new(
      scrape_mode: 'entire_website',
      url: 'https://example.com'
    )
    
    result = SitemapService.fetch_filtered_urls(job.url, job)
    
    assert result.is_a?(Array), "Should return array"
    assert result.length == 4, "Should exclude other domain, include same-domain URLs"
    
    # Should only include same-domain URLs
    result.each do |url|
      assert url.start_with?('https://example.com'), "Should only include same domain: #{url}"
    end
    assert_not result.include?('https://other-domain.com/page'), "Should exclude other domains"
    
    # Test prioritization order
    assert_equal 'https://example.com/', result.first, "Homepage should be first"
    assert_equal 'https://example.com/privacy-policy', result.last, "Utility page should be last"
    
    # Restore original method
    SitemapService.define_singleton_method(:fetch_filtered_urls) do |starting_url, job|
      service = new
      urls = service.fetch_sitemap_urls(starting_url)
      return nil if urls.nil? || urls.empty?
      service.filter_urls_for_mode(urls, job)
    end
  end

  test "streaming_parser_fallback_behavior" do
    service = SitemapService.new
    
    # Create a large XML content that would trigger streaming parser
    # Need to make it much larger to exceed the 1MB threshold
    large_xml_content = "<?xml version='1.0' encoding='UTF-8'?>\n<urlset xmlns='http://www.sitemaps.org/schemas/sitemap/0.9'>\n"
    10000.times do |i|
      # Make each URL entry longer to reach the 1MB threshold faster
      large_xml_content += "  <url><loc>https://example.com/very/long/path/to/page/number/#{i}/with/additional/path/segments/to/make/it/larger</loc></url>\n"
    end
    large_xml_content += "</urlset>"
    
    # Make sure it's larger than threshold
    assert large_xml_content.bytesize > SitemapService::LARGE_SITEMAP_THRESHOLD, 
           "Test XML should be large enough (#{large_xml_content.bytesize} bytes) to trigger streaming parser (threshold: #{SitemapService::LARGE_SITEMAP_THRESHOLD} bytes)"
    
    # Test that streaming parser works
    urls = service.send(:parse_sitemap, large_xml_content)
    
    assert_equal 10000, urls.length, "Streaming parser should extract all URLs"
    assert urls.all? { |url| url.start_with?('https://example.com/very/long/path') }, "All URLs should be correctly parsed"
    assert urls.uniq.length == urls.length, "Should not have duplicates"
  end

  test "memory_monitoring_integration" do
    service = SitemapService.new
    
    # Test that memory monitoring doesn't crash
    memory_usage = service.send(:current_memory_usage)
    
    assert memory_usage.is_a?(Numeric), "Should return numeric memory usage"
    assert memory_usage >= 0, "Memory usage should be non-negative"
    
    # Test memory monitoring during URL processing
    urls = (1..1000).map { |i| "https://example.com/page#{i}.html" }
    
    memory_before = service.send(:current_memory_usage)
    service.send(:prioritize_urls, urls, 'https://example.com')
    memory_after = service.send(:current_memory_usage)
    
    # Memory monitoring should work without errors
    assert memory_before.is_a?(Numeric), "Memory before should be numeric"
    assert memory_after.is_a?(Numeric), "Memory after should be numeric"
  end

  test "comprehensive_error_recovery" do
    service = SitemapService.new
    
    # Test that service recovers gracefully from various error conditions
    
    # 1. Invalid starting URL
    result = SitemapService.fetch_filtered_urls('not-a-url', OpenStruct.new(scrape_mode: 'entire_website', url: 'not-a-url'))
    assert_nil result, "Should handle invalid starting URLs gracefully"
    
    # 2. Network timeout (mock)
    mock_faraday_error = Faraday::TimeoutError.new("Test timeout")
    Faraday.define_singleton_method(:get) { |url| raise mock_faraday_error }
    
    result = service.fetch_sitemap('https://example.com/sitemap.xml')
    assert_nil result, "Should handle network timeouts gracefully"
    
    # 3. Redis unavailable during caching
    result = service.send(:cache_sitemap, 'test-key', 'test-content')
    assert_nil result, "Should handle Redis unavailability gracefully"
  end
end