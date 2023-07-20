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
  # Public profile routes
  get '/profiles/:id/photos', to: 'public_profiles#photo', as: 'public_photo'
  get 'profiles/:id/albums', to: 'public_profiles#album', as: 'public_album'
  get 'profiles/:id/followings', to: 'public_profiles#following', as: 'public_followings'
  get 'profiles/:id/followers', to: 'public_profiles#follower', as: 'public_followers'
  # follow route
  patch '/follow/unfollow/:follower_id/:followed_id', to: 'follows#unfollow', as: 'unfollow'
  patch '/follow/:follower_id/:followed_id', to: 'follows#follow', as: 'follow'

  root 'main#home'
end
