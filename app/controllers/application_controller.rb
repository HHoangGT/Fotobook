class ApplicationController < ActionController::Base
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :authenticate_user!

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: %i[fname lname])
    devise_parameter_sanitizer.permit(:account_update, keys: %i[email fname lname password avatar])
  end
end
