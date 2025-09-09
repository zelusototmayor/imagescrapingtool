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
end