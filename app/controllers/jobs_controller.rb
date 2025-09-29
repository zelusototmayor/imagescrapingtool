class JobsController < ApplicationController
  protect_from_forgery except: [:create]
  
  before_action :find_job, only: [:show, :download_zip, :download_manifest]

  def create
    @job = Job.new(job_params)
    @job.user = current_user if user_signed_in?

    if @job.save
      ScrapeJob.perform_async(@job.uuid)
      render json: { job_id: @job.uuid }, status: :created
    else
      render json: { errors: @job.errors.full_messages }, status: :unprocessable_content
    end
  end

  def show
    render json: {
      status: @job.status,
      progress: @job.progress,
      message: @job.message,
      pages_crawled: @job.pages_crawled,
      images_found: @job.images_found
    }
  end

  def download_zip
    session_id = session.id&.to_s || request.session_options[:id]
    ip_address = request.remote_ip

    unless @job.can_download?(current_user, session_id, ip_address)
      error_message = get_download_error_message(current_user, session_id, ip_address)
      render json: { error: error_message }, status: :forbidden
      return
    end

    zip_path = @job.zip_path(current_user, session_id, ip_address)
    unless File.exist?(zip_path)
      render json: { error: 'ZIP file not found' }, status: :not_found
      return
    end

    # Record the download
    @job.record_download!(current_user, session_id, ip_address)

    send_file zip_path,
              filename: "imagesweep-#{@job.uuid}.zip",
              type: 'application/zip',
              disposition: 'attachment'
  end

  def download_manifest
    session_id = session.id&.to_s || request.session_options[:id]
    ip_address = request.remote_ip

    unless @job.can_download?(current_user, session_id, ip_address)
      error_message = get_download_error_message(current_user, session_id, ip_address)
      render json: { error: error_message }, status: :forbidden
      return
    end

    manifest_path = @job.manifest_path(current_user, session_id, ip_address)
    unless File.exist?(manifest_path)
      render json: { error: 'Manifest not found' }, status: :not_found
      return
    end

    # Record the download (manifest counts as a download)
    @job.record_download!(current_user, session_id, ip_address)

    send_file manifest_path,
              filename: "manifest-#{@job.uuid}.json",
              type: 'application/json',
              disposition: 'attachment'
  end

  private

  def find_job
    @job = Job.find_by!(uuid: params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Job not found' }, status: :not_found
  end

  def job_params
    params.require(:job).permit(:url, :render_js, :scrape_mode)
  end

  def get_download_error_message(current_user, session_id, ip_address)
    if current_user
      if current_user.download_limit_reached?
        "Download limit reached. Upgrade to premium for unlimited downloads."
      elsif @job.already_downloaded?(current_user, session_id, ip_address)
        "This job has already been downloaded."
      else
        "Job not ready for download"
      end
    else
      anonymous_downloads = Download.anonymous
                                   .for_session(session_id)
                                   .for_ip(ip_address)
                                   .count
      if anonymous_downloads >= 1
        "Free download limit reached. Sign up for more downloads."
      elsif @job.already_downloaded?(current_user, session_id, ip_address)
        "This job has already been downloaded."
      else
        "Job not ready for download"
      end
    end
  end
end