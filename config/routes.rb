Rails.application.routes.draw do
  constraints(lambda { |req| req.ssl? || !Rails.env.production? }) do
    # Authentication routes
    get 'login', to: 'auth#login'
    
    # Main routes
    get 'dashboard', to: 'dashboard#index'
    root 'dashboard#index'

    namespace :api do
      namespace :v1 do
        # Debug routes 
        get 'debug/state', to: 'debug#state'
        get 'debug/cookie_info', to: 'debug#cookie_info'

        # Auth routes
        resource :auth, controller: :auth, only: [] do
          collection do
            post :check_device
            get :check_device
            post :phone_login
            post :verify_code
            post :verify_handle
            get :verify_handle
            post :update_handle
            post :logout
            post :verify_guid
            post :verify_guid_code
            post :resend_code 
          end
        end
        
        # Device routes
        resources :devices, only: [:index] do
          collection do
            get :status
            post :reset
            post :sync
          end
        end
        
        # User routes
        resource :user, controller: :user, only: [] do
          collection do
            get :data
            post :update_handle
          end
        end
      end
    end

    # PWA routes
    get '/manifest.json', to: 'pwa#manifest'
    get '/service-worker.js', to: 'pwa#service_worker'
  end

  # Redirect all non-SSL requests to SSL in production
  if Rails.env.production?
    match '*path', to: redirect { |params, request|
      "https://#{request.host}#{request.fullpath}"
    }, via: [:get, :post]
  end
end
