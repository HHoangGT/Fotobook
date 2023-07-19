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
  get '/profiles/followers', to: 'profiles#personalpagefollower'
  get '/profiles/followings', to: 'profiles#personalpagefollowing'
  # follow route
  patch '/follow/unfollow/:follower_id/:followed_id', to: 'follows#unfollow', as: 'unfollow'
  patch '/follow/:follower_id/:followed_id', to: 'follows#follow', as: 'follow'

  root 'main#home'
end
