# Playwright Process Management Fixes

This document outlines the fixes applied to resolve CPU overload caused by accumulated Playwright browser processes.

## Problem Summary
- Playwright browser processes were not being properly cleaned up when jobs timed out or failed
- 2-minute job timeout was too aggressive, causing frequent failures  
- No resource limits on containers allowed runaway processes to consume all CPU
- No monitoring or cleanup mechanisms for orphaned processes

## Implemented Solutions

### 1. Enhanced Playwright Resource Management
**File:** `app/services/image_scraper.rb`
- Added explicit browser lifecycle management with proper cleanup in `ensure` blocks
- Increased timeouts to more realistic values (90 seconds total, 45 seconds for operations)
- Added browser launch arguments to reduce resource usage
- Implemented `cleanup_browser_processes` method to kill orphaned processes

### 2. Improved Job Configuration
**Files:** `app/jobs/scrape_job.rb`, `.env`
- Increased `JOB_TIMEOUT_MINUTES` from 2 to 5 minutes
- Added cleanup on job timeout and error conditions
- Better error logging and resource cleanup

### 3. Automated Process Monitoring
**File:** `lib/tasks/cleanup.rake`
- `rails imagesweep:cleanup_browsers` - Clean up orphaned browser processes
- `rails imagesweep:monitor_browsers` - Monitor browser process usage
- `rails imagesweep:full_cleanup` - Complete cleanup (jobs + browsers)

### 4. Container Resource Limits
**File:** `config/deploy.yml`
- Web containers: 1GB RAM, 0.5 CPU cores
- Worker containers: 2GB RAM, 1.0 CPU cores  
- Health checks every 10 seconds
- Rolling deployment with proper drain timeout

### 5. Health Monitoring
**Files:** `config/routes.rb`, `app/controllers/application_controller.rb`
- `/health` endpoint monitors browser processes, Redis, database
- Warns when browser process count exceeds 10
- Returns 503 status if critical services are down

### 6. Automated Cleanup
**File:** `bin/cleanup-cron`
- Cron script for automated cleanup every 2 hours
- Add to crontab: `0 */2 * * * /path/to/imagesweep/bin/cleanup-cron`

## Deployment Hooks
- **Pre-deploy:** Clean up browser processes before new deployment
- **Post-deploy:** Monitor browser processes after deployment

## Monitoring Commands

```bash
# Monitor browser processes
rails imagesweep:monitor_browsers

# Clean up orphaned processes  
rails imagesweep:cleanup_browsers

# Full system cleanup
rails imagesweep:full_cleanup

# Check application health
curl http://your-server/health
```

## Expected Results
- Eliminated CPU overload from accumulated browser processes
- Improved job completion rates (5-minute timeout vs 2-minute)
- Container resource limits prevent runaway processes
- Automated monitoring and cleanup prevents future accumulation
- Rolling deployments ensure clean shutdowns

## Emergency Cleanup
If browser processes are still consuming too much CPU:

```bash
# Kill all headless browser processes
pkill -f "chromium.*--headless"
pkill -f "chrome.*--headless"

# Force kill if needed
pkill -9 -f "chromium.*--headless" 
pkill -9 -f "chrome.*--headless"
```