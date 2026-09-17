Rails.application.routes.draw do
  todo_routes = lambda do |api:|
    resources :lists, except: (api ? %i[new edit] : []) do
      resources :todos, only: :create
      if Rails.configuration.x.features.archive
        resource :archive, only: %i[create destroy], module: :lists
      end
    end
    resources :todos, only: (api ? %i[show update destroy] : %i[show edit update destroy]) do
      resource :completion, only: %i[create destroy], module: :todos
    end
  end

  root "lists#index"
  todo_routes.call(api: false)

  scope "/api", as: :api, defaults: { format: :json } do
    todo_routes.call(api: true)
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
