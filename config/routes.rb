require 'sidekiq/web'

Rails.application.routes.draw do
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

  # Stripe billing stubs for later
  post '/billing/checkout', to: 'billing#checkout'

  # Home page
  root 'home#index'
  get '/demo', to: 'home#demo'
end
