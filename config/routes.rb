Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Dashboard for monitoring agent activities
  get "dashboard" => "dashboard#index", as: :dashboard
  
  # Project management
  resources :projects do
    member do
      post :kickoff
      post :pause
      post :resume
    end
    
    # Nested tasks under projects
    resources :tasks
  end
  
  # Tasks can also be accessed directly
  resources :tasks do
    member do
      post :activate
      post :pause
      post :resume
    end
  end
  
  # Agent activities management
  resources :agent_activities, only: [:show] do
    member do
      post :pause
      post :resume
    end
  end
  
  # Human input requests
  resources :human_input_requests, only: [:show] do
    member do
      get :respond
      post :submit_response
      post :ignore
    end
  end

  # Defines the root path route ("/")
  namespace :admin do
    mount MissionControl::Jobs::Engine, at: "/jobs"
  end

  # Root route goes to projects index
  root "projects#index"
end
