require 'zip'

class ZipCreator
  def initialize(job, scraper_results)
    @job = job
    @results = scraper_results
  end

  def create
    create_manifest
    create_zip_archive
  end

  private

  def create_manifest
    manifest = {
      jobId: @job.uuid,
      site: UrlValidator.new(@job.url).origin,
      startedAt: @job.created_at.iso8601,
      pagesCrawled: @results[:pages_crawled],
      imagesTotalFound: @results[:images_total],
      imagesIncluded: @results[:images_included],
      truncated: @results[:truncated],
      images: @results[:images].map do |image|
        {
          filename: image[:filename],
          sourceUrl: image[:source_url],
          foundOn: image[:found_on],
          category: image[:category],
          width: image[:width],
          height: image[:height],
          mime: image[:mime],
          domContext: {
            tag: image[:dom_context][:tag],
            alt: image[:dom_context][:alt],
            classes: image[:dom_context][:classes] || [],
            id: image[:dom_context][:id],
            positionY: image[:dom_context][:position_y] || 0
          }
        }
      end
    }

    manifest_path = File.join(@job.artifact_dir, 'manifest.json')
    File.write(manifest_path, JSON.pretty_generate(manifest))
  end

  def create_zip_archive
    zip_path = File.join(@job.artifact_dir, 'imagesweep.zip')
    images_dir = File.join(@job.artifact_dir, 'images')
    manifest_path = File.join(@job.artifact_dir, 'manifest.json')

    Zip::File.open(zip_path, Zip::File::CREATE) do |zipfile|
      # Add manifest
      zipfile.add('manifest.json', manifest_path)

      # Add all images
      Dir.glob(File.join(images_dir, '**', '*')).each do |file_path|
        next unless File.file?(file_path)

        # Get relative path within images directory
        relative_path = Pathname.new(file_path).relative_path_from(Pathname.new(images_dir))
        zipfile.add(relative_path.to_s, file_path)
      end
    end

    Rails.logger.info "Created ZIP archive at #{zip_path}"
  end
end