class AdminController < ApplicationController
  # Add basic auth protection - change this password!
  http_basic_authenticate_with name: "admin", password: "your_admin_password_here"

  def users
    @users = User.includes(:jobs, :downloads).order(created_at: :desc)
    @total_users = @users.count
    @premium_users = @users.where(subscription_status: :premium).count
    @free_users = @users.where(subscription_status: :free).count
  end

  def make_premium
    user = User.find(params[:id])
    user.update!(subscription_status: :premium)
    redirect_to admin_users_path, notice: "#{user.email} is now premium!"
  end

  def make_free
    user = User.find(params[:id])
    user.update!(subscription_status: :free)
    redirect_to admin_users_path, notice: "#{user.email} is now free tier!"
  end

  def reset_downloads
    user = User.find(params[:id])
    user.update!(downloads_used: 0)
    redirect_to admin_users_path, notice: "Downloads reset for #{user.email}!"
  end
end