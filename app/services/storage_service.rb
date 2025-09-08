class StorageService
  def self.instance
    @instance ||= new
  end

  def initialize
    @adapter = Rails.env.production? ? :s3 : :local
  end

  def store_file(local_path, key)
    case @adapter
    when :s3
      store_to_s3(local_path, key)
    when :local
      store_locally(local_path, key)
    end
  end

  def file_url(key)
    case @adapter
    when :s3
      s3_url(key)
    when :local
      local_url(key)
    end
  end

  def delete_file(key)
    case @adapter
    when :s3
      delete_from_s3(key)
    when :local
      delete_locally(key)
    end
  end

  private

  def store_to_s3(local_path, key)
    # TODO: Implement S3 storage when needed
    # For now, just use local storage even in production
    store_locally(local_path, key)
  end

  def store_locally(local_path, key)
    destination = File.join(Rails.root, 'storage', key)
    FileUtils.mkdir_p(File.dirname(destination))
    FileUtils.cp(local_path, destination)
    key
  end

  def s3_url(key)
    # TODO: Return S3 URL when implemented
    local_url(key)
  end

  def local_url(key)
    "/storage/#{key}"
  end

  def delete_from_s3(key)
    # TODO: Implement S3 deletion
    delete_locally(key)
  end

  def delete_locally(key)
    path = File.join(Rails.root, 'storage', key)
    File.delete(path) if File.exist?(path)
  end
end