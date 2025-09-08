class JobsController < ApplicationController
  protect_from_forgery except: [:create]
  
  before_action :find_job, only: [:show, :download_zip, :download_manifest]

  def create
    @job = Job.new(job_params)
    
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
    unless @job.can_download?
      render json: { error: 'Job not ready for download' }, status: :forbidden
      return
    end

    zip_path = @job.zip_path
    unless File.exist?(zip_path)
      render json: { error: 'ZIP file not found' }, status: :not_found
      return
    end

    send_file zip_path,
              filename: "imagesweep-#{@job.uuid}.zip",
              type: 'application/zip',
              disposition: 'attachment'
  end

  def download_manifest
    unless @job.can_download?
      render json: { error: 'Job not ready for download' }, status: :forbidden
      return
    end

    manifest_path = @job.manifest_path
    unless File.exist?(manifest_path)
      render json: { error: 'Manifest not found' }, status: :not_found
      return
    end

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
end