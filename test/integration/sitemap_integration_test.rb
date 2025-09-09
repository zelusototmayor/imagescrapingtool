require "test_helper"

class SitemapIntegrationTest < ActiveSupport::TestCase
  def setup
    @job = Job.new(
      url: 'https://example.com/products',
      scrape_mode: 'subpath_only',
      status: 'queued',
      uuid: SecureRandom.uuid
    )
    @job.send(:set_artifact_dir)
    @job.save!
    
    @scraper = ImageScraper.new(@job)
  end

  test "SitemapService integration is properly called" do
    # Test that the SitemapService method exists and can be called
    assert_respond_to SitemapService, :fetch_filtered_urls
    
    # Test with a nil response (no sitemap found)
    result = SitemapService.fetch_filtered_urls('https://nonexistent-domain-12345.com', @job)
    assert_nil result
  end

  test "ImageScraper integration preserves fallback behavior" do
    # Test that when sitemap returns nil, the scraper falls back to original behavior
    original_queue_size = @scraper.instance_variable_get(:@page_queue).size
    
    # Override scrape_page and finalize_results to avoid actual HTTP calls
    def @scraper.scrape_page(url)
      # Do nothing - just avoid HTTP calls
    end
    
    def @scraper.finalize_results
      { pages_crawled: 0, images: [] }
    end
    
    # Call the method - it should not raise errors
    assert_nothing_raised do
      @scraper.send(:scrape_with_subpath_restriction)
    end
    
    # Verify the job was updated with progress
    @job.reload
    assert @job.progress >= 5, "Expected progress to be updated to at least 5%, got #{@job.progress}%"
  end

  test "ImageScraper integration works for entire website mode" do
    @job.update!(scrape_mode: 'entire_website')
    
    # Override methods to avoid HTTP calls
    def @scraper.scrape_page(url)
      # Do nothing
    end
    
    def @scraper.finalize_results
      { pages_crawled: 0, images: [] }
    end
    
    # Should not raise errors
    assert_nothing_raised do
      @scraper.send(:scrape_entire_website)
    end
    
    # Verify the job was updated
    @job.reload
    assert @job.progress >= 5, "Expected progress to be updated to at least 5%, got #{@job.progress}%"
  end

  test "integration preserves existing functionality for current_page mode" do
    @job.update!(scrape_mode: 'current_page')
    
    # Override scrape_page to avoid HTTP calls
    def @scraper.scrape_page(url)
      # Do nothing
    end
    
    def @scraper.finalize_results
      { pages_crawled: 1, images: [] }
    end
    
    # Current page mode should not use sitemap
    assert_nothing_raised do
      @scraper.send(:scrape_current_page_only)
    end
    
    # Verify it worked
    assert_equal 1, @scraper.instance_variable_get(:@pages_crawled)
  end
end