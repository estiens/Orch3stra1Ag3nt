require 'vcr'

VCR.configure do |config|
  config.cassette_library_dir = "spec/fixtures/vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Don't record sensitive data
  config.filter_sensitive_data('<OPEN_ROUTER_API_KEY>') { ENV['OPEN_ROUTER_API_KEY'] }

  # Allow connections to localhost
  config.ignore_localhost = true

  # Allow real connections when cassettes don't exist for development
  # But force mocking in CI environment
  record_mode = ENV['CI'] ? :none : :once
  config.default_cassette_options = {
    record: record_mode,
    match_requests_on: [ :method, :uri, :body ],
    allow_playback_repeats: true
  }

  # Raise an error when a request is made in testing that's not being recorded/mocked
  config.allow_http_connections_when_no_cassette = false
end
