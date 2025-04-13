# Configure research tools
Rails.application.config.after_initialize do
  Rails.logger.info "Configuring research tools..."

  # Validate API keys for search tools
  serpapi_key = ENV["SERPAPI_API_KEY"]
  perplexity_key = ENV["PERPLEXITY_API_KEY"]

  # Log configuration status
  if serpapi_key.present?
    Rails.logger.info "SerpAPI search tool configured with API key"
  else
    Rails.logger.warn "SerpAPI search tool not configured: SERPAPI_API_KEY not set"
  end

  if perplexity_key.present?
    Rails.logger.info "Perplexity search tool configured with API key"
  else
    Rails.logger.warn "Perplexity search tool not configured: PERPLEXITY_API_KEY not set"
  end

  # Configure mechanize web scraper
  begin
    agent = Mechanize.new
    agent.user_agent_alias = "Mac Safari"
    Rails.logger.info "Mechanize web scraper configured successfully"
  rescue => e
    Rails.logger.error "Error configuring Mechanize: #{e.message}"
  end

  # Define some safe domains for initial testing - can be expanded later
  Rails.application.config.safe_domains = [
    "en.wikipedia.org",
    "github.com",
    "stackoverflow.com",
    "ruby-doc.org",
    "rubyonrails.org",
    "rubygems.org"
  ]

  Rails.logger.info "Research tools configuration complete"
end
