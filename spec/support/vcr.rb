require 'vcr'

VCR.configure do |config|
  config.cassette_library_dir = "spec/fixtures/vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Don't record sensitive data
  config.filter_sensitive_data('<OPEN_ROUTER_API_KEY>') { ENV['OPEN_ROUTER_API_KEY'] }
  config.filter_sensitive_data('<HUGGINGFACE_API_TOKEN>') { ENV['HUGGINGFACE_API_TOKEN'] }

  # Allow connections to localhost
  config.ignore_localhost = true

  # Allow real connections when cassettes don't exist for development
  # But force mocking in CI environment
  record_mode = ENV['CI'] ? :none : :new_episodes
  config.default_cassette_options = {
    record: record_mode,
    match_requests_on: [ :method, :uri ],  # Remove body matching for more flexibility
    allow_playback_repeats: true
  }

  # Allow HTTP connections when no cassette is used
  config.allow_http_connections_when_no_cassette = true
  
  # Add a debug logger
  config.debug_logger = File.open(File.join(Rails.root, 'log', 'vcr.log'), 'w') if Rails.env.test?
end
