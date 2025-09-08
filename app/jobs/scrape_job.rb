class ScrapeJob
  include Sidekiq::Job
  sidekiq_options retry: 1

  def perform(job_uuid)
    @job = Job.find_by!(uuid: job_uuid)
    @job.update!(status: :running, progress: 0)
    
    timeout_seconds = ENV.fetch('JOB_TIMEOUT_MINUTES', 5).to_i * 60
    
    Timeout.timeout(timeout_seconds) do
      execute_scrape
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "ScrapeJob failed: Job with UUID #{job_uuid} not found in database"
    raise # Re-raise so Sidekiq can handle the failure properly
  rescue Timeout::Error
    Rails.logger.error "ScrapeJob timed out for #{@job&.uuid || job_uuid} after #{timeout_seconds / 60} minutes"
    cleanup_job_resources
    @job&.update!(
      status: :error,
      message: "Job timed out after #{timeout_seconds / 60} minutes"
    )
  rescue => e
    Rails.logger.error "ScrapeJob failed for #{@job&.uuid || job_uuid}: #{e.message}"
    Rails.logger.error "Backtrace: #{e.backtrace.first(3).join('\n')}"
    cleanup_job_resources
    @job&.update!(
      status: :error,
      message: "Scraping failed: #{e.message}"
    )
  end

  private

  def execute_scrape
    Rails.logger.info "Starting scrape job for #{@job.uuid} - URL: #{@job.url}"
    
    # Check robots.txt
    Rails.logger.info "Checking robots.txt for #{@job.url}"
    unless RobotsChecker.allowed?(@job.url)
      Rails.logger.warn "Robots.txt disallows scraping for #{@job.url}"
      @job.update!(
        status: :error,
        message: 'Scraping disallowed by robots.txt. Please respect the site\'s robots.txt file.'
      )
      return
    end
    Rails.logger.info "Robots.txt check passed for #{@job.url}"

    @job.update!(progress: 10, message: 'Starting to crawl pages...')
    Rails.logger.info "Updated progress to 10% for job #{@job.uuid}"

    Rails.logger.info "Creating ImageScraper for job #{@job.uuid}"
    scraper = ImageScraper.new(@job)
    Rails.logger.info "Starting scrape process for job #{@job.uuid}"
    results = scraper.scrape
    Rails.logger.info "Scrape completed for job #{@job.uuid}. Results: #{results.inspect}"

    @job.update!(
      progress: 90,
      message: 'Creating ZIP archive and manifest...',
      pages_crawled: results[:pages_crawled],
      images_found: results[:images_total]
    )

    # Create ZIP and manifest
    zip_creator = ZipCreator.new(@job, results)
    zip_creator.create

    @job.update!(
      status: :done,
      progress: 100,
      message: results[:truncated] ? 
        "Completed! Found #{results[:images_total]} images, included #{results[:images_included]}." :
        "Completed! Found #{results[:images_total]} images."
    )
  end

  def cleanup_job_resources
    begin
      # Kill any orphaned browser processes for this job
      system('pkill -f "chromium.*--headless" >/dev/null 2>&1')
      system('pkill -f "chrome.*--headless" >/dev/null 2>&1')
      Rails.logger.info "Cleaned up browser processes for job #{@job.uuid}"
    rescue => e
      Rails.logger.warn "Error during job resource cleanup: #{e.message}"
    end
  end
end