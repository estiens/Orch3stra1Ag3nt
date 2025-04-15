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
    match_requests_on: [:method, :host, :path],  # More lenient matching for better cache hits
    allow_playback_repeats: true,
    serialize_with: :yaml,  # Ensure YAML serialization for better readability
    preserve_exact_body_bytes: false  # Don't preserve exact bytes for better matching
  }

  # Allow HTTP connections when no cassette is used
  config.allow_http_connections_when_no_cassette = true
  
  # Add a debug logger
  config.debug_logger = File.open(File.join(Rails.root, 'log', 'vcr.log'), 'w') if Rails.env.test?
  
  # Ignore certain hosts if needed
  # config.ignore_hosts 'localhost', '127.0.0.1'
  
  # Configure a custom matcher if needed
  # config.register_request_matcher :my_matcher do |request_1, request_2|
  #   # Custom matching logic
  # end
end
