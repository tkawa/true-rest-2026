Rails.application.routes.draw do
  # 表現はスコープで固定し、Accept ヘッダや拡張子（.json / .html）で
  # 反対側の表現に到達できないようにする（format: false で拡張子の経路を閉じる）。
  todo_routes = lambda do |api:|
    resources :lists, format: false, except: (api ? %i[new edit] : []) do
      resources :todos, only: :create, format: false
      if Rails.configuration.x.features.archive
        resource :archive, only: %i[create destroy], module: :lists, format: false
      end
    end
    resources :todos, format: false, only: (api ? %i[show update destroy] : %i[show edit update destroy]) do
      resource :completion, only: %i[create destroy], module: :todos, format: false
    end
  end

  scope defaults: { format: :html } do
    root "lists#index"
    todo_routes.call(api: false)
  end

  scope "/api", as: :api, defaults: { format: :json } do
    todo_routes.call(api: true)

    # 仕様書にないURLを試したときも、HTMLの404ページではなくJSONを返す。
    match "(*unmatched)", to: "api_not_found#show", via: :all, format: false
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
