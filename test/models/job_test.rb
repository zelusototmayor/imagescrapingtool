require "test_helper"

class JobTest < ActiveSupport::TestCase
  test "should create job with valid URL" do
    job = Job.new(url: "https://example.com", max_pages: 1)
    assert job.valid?
    assert job.save
    assert job.uuid.present?
    assert job.artifact_dir.present?
  end

  test "should reject invalid URLs" do
    job = Job.new(url: "invalid-url", max_pages: 1)
    assert_not job.valid?
    assert job.errors[:url].present?
  end

  test "should reject localhost URLs" do
    job = Job.new(url: "http://localhost:4000", max_pages: 1)
    assert_not job.valid?
    assert job.errors[:url].present?
  end

  test "should reject private IP URLs" do
    job = Job.new(url: "http://192.168.1.1", max_pages: 1)
    assert_not job.valid?
    assert job.errors[:url].present?
  end

  test "should enforce max_pages limits" do
    job = Job.new(url: "https://example.com", max_pages: 15)
    assert_not job.valid?
    assert job.errors[:max_pages].present?
  end

  test "should set default values" do
    job = Job.create!(url: "https://example.com")
    assert_equal true, job.render_js
    assert_equal 1, job.max_pages
    assert_equal true, job.restrict_to_subpath
    assert_equal "queued", job.status
    assert_equal 0, job.progress
    assert_equal true, job.is_paid
  end

  test "can_download? should work correctly" do
    job = Job.create!(url: "https://example.com", status: :done)
    
    # Without artifact directory
    assert_not job.can_download?
    
    # With artifact directory but no images folder
    FileUtils.mkdir_p(job.artifact_dir)
    assert_not job.can_download?
    
    # With images folder
    FileUtils.mkdir_p(File.join(job.artifact_dir, 'images'))
    assert job.can_download?
    
    # Cleanup
    FileUtils.rm_rf(job.artifact_dir)
  end
end
