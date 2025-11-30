CarrierWave.configure do |config|
  config.fog_credentials = {
    provider: 'AWS', # required
    aws_access_key_id: ENV['PUBLIC'], # required unless using use_iam_profile
    aws_secret_access_key: ENV['PRIVATE'], # required unless using use_iam_profile
    region: 'us-east-1' # optional, defaults to 'us-east-1'
  }
  config.fog_directory = 'de-demo-2025-1' # required
end
