require 'sidekiq/web'

Rails.application.routes.draw do
  devise_for :users
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  
  # Custom health check endpoint with browser process monitoring
  get "health" => "application#health", as: :health_check

  # Sidekiq Web UI (only in development for now)
  mount Sidekiq::Web => '/sidekiq' if Rails.env.development?

  # ImageSweep API routes
  post '/jobs', to: 'jobs#create'
  get '/jobs/:id', to: 'jobs#show'
  get '/jobs/:id/download.zip', to: 'jobs#download_zip'
  get '/jobs/:id/manifest.json', to: 'jobs#download_manifest'

  # Stripe billing routes
  post '/billing/checkout', to: 'billing#checkout'
  post '/billing/webhook', to: 'billing#webhook'

  # User dashboard
  get '/dashboard', to: 'dashboard#index'

  # Admin routes
  get '/admin/users', to: 'admin#users'
  post '/admin/users/:id/make_premium', to: 'admin#make_premium', as: 'admin_make_premium'
  post '/admin/users/:id/make_free', to: 'admin#make_free', as: 'admin_make_free'
  post '/admin/users/:id/reset_downloads', to: 'admin#reset_downloads', as: 'admin_reset_downloads'

  # Home page
  root 'home#index'
  get '/pricing', to: 'home#pricing'
end
