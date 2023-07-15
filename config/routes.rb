Rails.application.routes.draw do
  devise_for :users

  devise_scope :user do
    get '/users/sign_out' => 'devise/sessions#destroy'
  end
  # Photo and albums routes
  scope :users do
    resources :photos, :albums, except: %i[index show]
  end
  # Profile routes
  get '/profiles/photos', to: 'profiles#personalpagephoto'
  get '/profiles/albums', to: 'profiles#personalpagealbum'

  root 'main#home'
end
