require "vcr"
require "webmock/rspec"

VCR.configure do |config|
  config.cassette_library_dir = "spec/cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Filter sensitive data
  config.filter_sensitive_data("<OPEN_ROUTER_API_KEY>") { ENV["OPEN_ROUTER_API_KEY"] }

  # Optionally ignore localhost
  config.ignore_localhost = true

  # Allow HTTP connections when no cassette is used (disable to enforce strict VCR usage)
  config.allow_http_connections_when_no_cassette = false
end
