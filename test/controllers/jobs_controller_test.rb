require "test_helper"

class JobsControllerTest < ActionDispatch::IntegrationTest
  def setup
    # Mock Sidekiq for tests
    Sidekiq::Testing.fake!
  end
  test "should create job with valid params" do
    assert_difference('Job.count') do
      post jobs_path, params: {
        job: {
          url: "https://example.com",
          render_js: true,
          max_pages: 2,
          restrict_to_subpath: false
        }
      }, as: :json
    end

    assert_response :created
    response_data = JSON.parse(response.body)
    assert response_data['job_id'].present?
    
    job = Job.find_by(uuid: response_data['job_id'])
    assert job.present?
    assert_equal "https://example.com/", job.url
    assert_equal true, job.render_js
    assert_equal 2, job.max_pages
    assert_equal false, job.restrict_to_subpath
  end

  test "should reject job with invalid URL" do
    assert_no_difference('Job.count') do
      post jobs_path, params: {
        job: {
          url: "invalid-url"
        }
      }, as: :json
    end

    assert_response :unprocessable_content
    response_data = JSON.parse(response.body)
    assert response_data['errors'].present?
  end

  test "should show job status" do
    job = Job.create!(url: "https://example.com", status: :running, progress: 50)
    
    get "/jobs/#{job.uuid}", as: :json
    
    assert_response :success
    response_data = JSON.parse(response.body)
    assert_equal "running", response_data['status']
    assert_equal 50, response_data['progress']
  end

  test "should return 404 for non-existent job" do
    get "/jobs/nonexistent", as: :json
    assert_response :not_found
  end

  test "should reject download for incomplete job" do
    job = Job.create!(url: "https://example.com", status: :queued)
    
    get "/jobs/#{job.uuid}/download.zip"
    assert_response :forbidden
  end
end