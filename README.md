# ImageSweep

A production-ready Rails application for scraping images from websites. Users provide a URL and ImageSweep crawls the site, downloads up to 200 images, organizes them by category (hero, product, logo, other), and provides them as a downloadable ZIP with metadata.

## Features

- **Modern UI**: Beautiful, responsive interface with glass morphism effects and smooth animations
- **Simple UX**: PDF converter-style interface with URL input and one-click scraping
- **Smart Crawling**: Supports both JavaScript rendering (Playwright) and static HTML parsing
- **Sitemap Discovery**: 10-50x faster page discovery using sitemap.xml with intelligent fallback to link crawling
- **URL Prioritization**: Smart ranking ensures most relevant pages are scraped first when hitting limits
- **Image Classification**: Automatically categorizes images as hero, product, logo, or other
- **Organized Output**: Images sorted into folders with descriptive filenames
- **Rate Limiting**: 10 jobs per hour per IP address
- **Robots.txt Compliance**: Respects website crawling permissions
- **Background Processing**: Uses Sidekiq for non-blocking job execution
- **Real-time Updates**: Live progress tracking with WebSocket-style polling

## Tech Stack

- **Backend**: Rails 8, Ruby 3.3, PostgreSQL, Redis
- **Frontend**: Tailwind CSS 4, vanilla JavaScript, ERB templates, Google Fonts (Inter)
- **Background Jobs**: Sidekiq
- **Web Scraping**: Playwright (headless Chrome) + Nokogiri fallback
- **File Processing**: RubyZip, FastImage
- **Security**: Rack::Attack rate limiting, URL validation

## UI Features

The application features a modern, beautiful interface designed with user experience in mind:

### Design System
- **Glass Morphism**: Semi-transparent cards with backdrop blur effects
- **Gradient Accents**: Beautiful blue-to-indigo gradients for primary actions
- **Modern Typography**: Inter font family for excellent readability
- **Responsive Layout**: Optimized for all device sizes from mobile to desktop

### Interactive Elements
- **Smooth Animations**: Hover effects, transitions, and micro-interactions
- **Enhanced Forms**: Better input styling with focus states and validation
- **Progress Indicators**: Beautiful progress bars and status updates
- **Error Handling**: Elegant error notifications with auto-dismiss

### Visual Improvements
- **Enhanced Cards**: Better shadows, borders, and hover effects
- **Icon Integration**: SVG icons throughout the interface
- **Color Coding**: Semantic colors for different states and actions
- **Loading States**: Animated spinners and progress indicators

## Quick Start

### Prerequisites

- Ruby 3.3+
- PostgreSQL 14+
- Redis 6+
- Node.js 18+ (for Playwright)

### Installation

1. **Clone and setup**:
   ```bash
   git clone <repository-url> imagesweep
   cd imagesweep
   bundle install
   ```

2. **Install Playwright browsers**:
   ```bash
   npx playwright install chromium
   ```

3. **Configure environment**:
   ```bash
   cp .env.example .env
   # Edit .env with your database and Redis URLs
   ```

4. **Setup database**:
   ```bash
   rails db:create db:migrate
   ```

5. **Start services**:
   ```bash
   # Terminal 1: Redis (if not running as service)
   redis-server
   
   # Terminal 2: Sidekiq worker
   bundle exec sidekiq
   
   # Terminal 3: Rails server
   rails server
   ```

6. **Visit** `http://localhost:4000`

## Configuration

### Environment Variables

```bash
# Database
DATABASE_URL=postgresql://localhost/imagesweep_development

# Redis
REDIS_URL=redis://localhost:6379/0

# Scraping Configuration
MAX_IMAGES=200                     # Hard limit per job
JOB_TIMEOUT_MINUTES=2             # Timeout per scraping job
USER_AGENT=ImageSweepBot/0.1      # Bot identification

# Sitemap Discovery (NEW in v1.1.0)
ENABLE_SITEMAP_SCRAPING=true      # Enable sitemap.xml discovery (default: true)
SITEMAP_CACHE_TTL=3600            # Sitemap cache time in seconds (default: 1 hour)
SITEMAP_DOWNLOAD_TIMEOUT=30       # Sitemap download timeout in seconds
MAX_SITEMAP_SIZE=10485760         # Max sitemap size in bytes (default: 10MB)
LARGE_SITEMAP_THRESHOLD=1048576   # Use streaming parser above this size (default: 1MB)
SITEMAP_DEPTH_PENALTY=10          # Points deducted per URL depth level
SITEMAP_SIMILARITY_BONUS=30       # Points added for URLs in same category
SITEMAP_UTILITY_PENALTY=50        # Points deducted for utility pages

# Rate Limiting
RATE_LIMIT_JOBS_PER_HOUR=10       # Jobs per IP per hour

# Cleanup
CLEANUP_DAYS=1                    # Days to keep job artifacts

# Stripe (future)
STRIPE_SECRET_KEY=sk_test_...
STRIPE_PRICE_ID=price_...
```

### Advanced Options

Users can configure:
- **Render JavaScript**: ON (default) for SPAs, OFF for static sites
- **Max Pages**: 1-10 pages to crawl (default: 1)
- **Restrict to Subpath**: Only crawl within initial URL path (default: ON)

## API Endpoints

### Create Job
```http
POST /jobs
Content-Type: application/json

{
  "job": {
    "url": "https://example.com",
    "render_js": true,
    "max_pages": 3,
    "restrict_to_subpath": true
  }
}
```

### Check Status
```http
GET /jobs/{job_id}
```

### Download Files
```http
GET /jobs/{job_id}/download.zip      # ZIP archive
GET /jobs/{job_id}/manifest.json     # Metadata
```

## Image Classification

Images are automatically categorized:

- **Hero**: Large images (≥1000px width), wide aspect ratios (≥2:1), og:image meta tags, above-fold content
- **Product**: Found on product/shop pages, contains product-related keywords in alt/class/id
- **Logo**: Small images (≤128px), contains logo/icon keywords
- **Other**: Everything else

## File Organization

```
imagesweep-{job-id}.zip
├── manifest.json              # Complete metadata
├── hero/
│   ├── 001_hero-banner.jpg
│   └── 002_main-hero.png
├── product/  
│   ├── 001_red-sneaker.jpg
│   └── 002_blue-jacket.webp
├── logo/
│   └── 001_company-logo.svg
└── other/
    ├── 001_thumbnail.jpg
    └── 002_icon.png
```

## Deployment

### Heroku/Render

1. Add buildpacks:
   ```bash
   # For Playwright
   heroku buildpacks:add https://github.com/mxschmitt/heroku-playwright-buildpack
   heroku buildpacks:add heroku/ruby
   ```

2. Set environment variables in dashboard or:
   ```bash
   heroku config:set MAX_IMAGES=200
   heroku config:set REDIS_URL=redis://...
   # etc.
   ```

3. Deploy:
   ```bash
   git push heroku main
   heroku run rails db:migrate
   ```

### DigitalOcean (Kamal)

1. Configure `config/deploy.yml`:
   ```yaml
   service: imagesweep
   image: imagesweep
   servers:
     web:
       hosts: ["your-server-ip"]
   ```

2. Deploy:
   ```bash
   kamal setup    # First time
   kamal deploy   # Updates
   ```

## Maintenance

### Cleanup Old Jobs

```bash
# Clean up jobs older than 1 day (default)
rails imagesweep:cleanup

# Custom retention period
CLEANUP_DAYS=3 rails imagesweep:cleanup

# View statistics
rails imagesweep:stats
```

### Monitoring

- **Sidekiq Web UI**: `http://localhost:4000/sidekiq` (development)
- **Application logs**: Standard Rails.logger
- **Job statistics**: `rails imagesweep:stats`

## Testing

```bash
# Run all tests
rails test

# Run specific test files
rails test test/models/job_test.rb
rails test test/controllers/jobs_controller_test.rb
rails test test/services/url_validator_test.rb

# Code quality
rubocop
brakeman
```

## Security Considerations

- **URL Validation**: Blocks localhost, private IPs, and invalid schemes
- **Robots.txt**: Respects crawling permissions (fails gracefully if blocked)
- **Rate Limiting**: Prevents abuse with Rack::Attack
- **File Safety**: Validates image types, size limits (20MB), safe temp directories
- **XSS Prevention**: No user content in views, JSON API responses only

## Troubleshooting

### Playwright Issues
```bash
# Reinstall browsers
npx playwright install chromium --force

# Check installation
npx playwright --version
```

### Job Failures
- Check Sidekiq logs: `tail -f log/sidekiq.log`
- Inspect failed jobs in Sidekiq Web UI
- Verify robots.txt allows crawling: `curl https://example.com/robots.txt`

### Performance
- Monitor Redis memory usage
- Consider upgrading to Redis Cluster for high volume
- Use CDN for static assets in production

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Run tests (`rails test`)
4. Commit changes (`git commit -m 'Add amazing feature'`)
5. Push to branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

- **Issues**: Create a GitHub issue
- **Email**: support@imagesweep.app
- **Documentation**: Check the source code comments for detailed implementation notes
