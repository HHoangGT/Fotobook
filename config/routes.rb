Rails.application.routes.draw do
  devise_for :users

  devise_scope :user do
    get '/users/sign_out' => 'devise/sessions#destroy'
  end
  # Photo routes
  scope :users do
    resources :photos, except: %i[index show]
  end
  # Profile routes
  get '/profiles/photos', to: 'profiles#personalpagephoto'

  root 'main#home'
end
