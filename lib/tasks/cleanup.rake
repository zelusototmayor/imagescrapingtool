namespace :imagesweep do
  desc "Clean up old job artifacts and database records"
  task cleanup: :environment do
    days_to_keep = ENV.fetch('CLEANUP_DAYS', 1).to_i
    
    puts "Cleaning up jobs older than #{days_to_keep} day(s)..."
    
    old_jobs = Job.old(days_to_keep)
    cleaned_count = 0
    
    old_jobs.find_each do |job|
      begin
        # Clean up artifacts
        job.cleanup_artifacts!
        
        # Delete the job record
        job.destroy!
        
        cleaned_count += 1
        puts "Cleaned up job #{job.uuid}"
      rescue => e
        Rails.logger.error "Failed to clean up job #{job.uuid}: #{e.message}"
        puts "ERROR: Failed to clean up job #{job.uuid}: #{e.message}"
      end
    end
    
    puts "Cleanup complete. Removed #{cleaned_count} old jobs."
    
    # Also clean up any orphaned temp directories
    temp_dir = File.join(Rails.root, 'storage', 'imagesweep')
    if Dir.exist?(temp_dir)
      Dir.glob(File.join(temp_dir, '*')).each do |dir|
        next unless File.directory?(dir)
        
        # Check if this directory is older than the retention period
        if File.stat(dir).mtime < days_to_keep.days.ago
          begin
            FileUtils.rm_rf(dir)
            puts "Cleaned up orphaned directory: #{dir}"
          rescue => e
            Rails.logger.error "Failed to clean up directory #{dir}: #{e.message}"
          end
        end
      end
    end
  end

  desc "Show statistics about jobs and storage usage"
  task stats: :environment do
    total_jobs = Job.count
    queued_jobs = Job.queued.count
    running_jobs = Job.running.count
    done_jobs = Job.done.count
    error_jobs = Job.error.count
    
    puts "=== ImageSweep Statistics ==="
    puts "Total jobs: #{total_jobs}"
    puts "Queued: #{queued_jobs}"
    puts "Running: #{running_jobs}"
    puts "Completed: #{done_jobs}"
    puts "Failed: #{error_jobs}"
    puts
    
    # Storage usage
    temp_dir = File.join(Rails.root, 'storage', 'imagesweep')
    if Dir.exist?(temp_dir)
      total_size = Dir.glob(File.join(temp_dir, '**', '*'))
                     .select { |f| File.file?(f) }
                     .sum { |f| File.size(f) }
      
      puts "Temp storage usage: #{(total_size / 1024.0 / 1024.0).round(2)} MB"
    else
      puts "Temp storage usage: 0 MB"
    end
    
    # Recent job stats
    puts
    puts "=== Recent Activity (last 24 hours) ==="
    recent_jobs = Job.where('created_at > ?', 24.hours.ago)
    puts "Jobs created: #{recent_jobs.count}"
    puts "Images scraped: #{recent_jobs.sum(:images_found)}"
    puts "Pages crawled: #{recent_jobs.sum(:pages_crawled)}"
  end

  desc "Clean up orphaned browser processes"
  task cleanup_browsers: :environment do
    puts "Cleaning up orphaned browser processes..."
    
    # Count processes before cleanup
    chromium_count = `pgrep -c -f 'chromium.*--headless' 2>/dev/null || echo 0`.strip.to_i
    chrome_count = `pgrep -c -f 'chrome.*--headless' 2>/dev/null || echo 0`.strip.to_i
    
    puts "Found #{chromium_count} Chromium processes and #{chrome_count} Chrome processes"
    
    if chromium_count > 0 || chrome_count > 0
      # Kill orphaned browser processes
      system('pkill -f "chromium.*--headless" >/dev/null 2>&1')
      system('pkill -f "chrome.*--headless" >/dev/null 2>&1')
      
      # Wait a moment for processes to terminate
      sleep(2)
      
      # Force kill if any remain
      system('pkill -9 -f "chromium.*--headless" >/dev/null 2>&1')
      system('pkill -9 -f "chrome.*--headless" >/dev/null 2>&1')
      
      puts "Browser processes cleaned up"
    else
      puts "No orphaned browser processes found"
    end
  end

  desc "Monitor browser process usage"
  task monitor_browsers: :environment do
    chromium_count = `pgrep -c -f 'chromium.*--headless' 2>/dev/null || echo 0`.strip.to_i
    chrome_count = `pgrep -c -f 'chrome.*--headless' 2>/dev/null || echo 0`.strip.to_i
    
    puts "=== Browser Process Monitor ==="
    puts "Chromium processes: #{chromium_count}"
    puts "Chrome processes: #{chrome_count}"
    puts "Total browser processes: #{chromium_count + chrome_count}"
    
    if chromium_count + chrome_count > 5
      puts "WARNING: High number of browser processes detected!"
      puts "Consider running: rails imagesweep:cleanup_browsers"
    end
    
    # Show memory usage of browser processes
    browser_memory = `ps -o pid,rss,command -C chromium,chrome 2>/dev/null | tail -n +2 | awk '{sum+=$2} END {print sum/1024}' | head -1`.strip
    puts "Browser memory usage: #{browser_memory.empty? ? '0' : browser_memory.to_f.round(1)} MB" if browser_memory
  end

  desc "Full system cleanup (jobs + browsers)"
  task full_cleanup: [:cleanup, :cleanup_browsers] do
    puts "Full system cleanup completed"
  end
end