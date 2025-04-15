require "httparty"
require "json"

# PerplexitySearchTool: Provides perplexity search capabilities
class PerplexitySearchTool
  extend Langchain::ToolDefinition

  define_function :search, description: "Search the web using Perplexity AI" do
    property :query, type: "string", description: "The search query", required: true
    property :focus, type: "string", description: "Search focus (web, academic, news, writing)", required: false
  end

  def initialize
    @api_key = ENV.fetch("PERPLEXITY_API_KEY", nil)
    raise "PERPLEXITY_API_KEY is not set cannot use PerplexitySearchTool" unless @api_key
  end

  # Add call method for compatibility with tests
  def call(query:, focus: "web")
    search(query: query, focus: focus)
  end

  def search(query:, focus: "web")
    @query = query
    @focus = validate_focus(focus)

    begin
      # Log the request for debugging
      Rails.logger.info("Perplexity API request to: #{base_url}")
      Rails.logger.info("Perplexity API headers: #{headers.to_json}")
      Rails.logger.info("Perplexity API request body: #{request_body.to_json}")

      response = HTTParty.post(
        base_url,
        headers: headers,
        body: request_body.to_json,
        timeout: 30
      )

      # Handle API response
      if response.success?
        data = JSON.parse(response.body)

        # Format the response based on the API response structure
        result = {
          query: @query,
          response: data.dig("choices", 0, "message", "content"),
          focus: @focus
        }

        # Add citation information if available
        if data["citations"]
          result[:citations] = data["citations"].map do |citation|
            {
              title: citation.split('/').last.to_s.gsub('-', ' ').capitalize,
              url: citation
            }
          end
        end

        result
      else
        # Enhanced error handling to provide more diagnostic information
        begin
          error_data = JSON.parse(response.body)
          
          # Handle different error formats
          error_message = if error_data.is_a?(Array)
                           error_data.join(", ")
                         elsif error_data.dig("error", "message")
                           error_data.dig("error", "message")
                         elsif error_data["error"]
                           error_data["error"]
                         elsif error_data["message"]
                           error_data["message"]
                         else
                           "Error details not available"
                         end

          Rails.logger.error("Perplexity API error: #{response.code} - #{error_message}")
          Rails.logger.error("Request body: #{request_body.to_json}")

          # Return a more user-friendly message that can be displayed to the user
          "No search results found. The search API returned an error: #{error_message}. Please try a different search query or try again later."
        rescue StandardError => e
          Rails.logger.error("Failed to parse error response: #{e.message}")
          Rails.logger.error("Raw response: #{response.body}")

          "No search results found. The search API returned an error. Please try a different search query or try again later."
        end
      end
    rescue => e
      Rails.logger.error("Error executing Perplexity search: #{e.message}")
      "No search results found due to a connection error: #{e.message}. Please try again later."
    end
  end

  private

  def validate_focus(focus)
    valid_focuses = %w[web academic news writing]

    focus = focus.to_s.downcase
    unless valid_focuses.include?(focus)
      Rails.logger.warn("Invalid focus: #{focus}. Defaulting to 'web'.")
      focus = "web"
    end
    focus
  end

  def base_url
    # Ensure the URL is exactly as specified in the documentation
    "https://api.perplexity.ai/chat/completions"
  end

  def headers
    {
      "Authorization" => "Bearer #{@api_key}",
      "Content-Type" => "application/json"
    }
  end
  def request_body
    # Format according to Perplexity API requirements
    body = {
      model: "sonar-pro",
      messages: [
        {
          role: "user",
          content: @query.to_s # Ensure it's a string
        }
      ],
      max_tokens: 300
    }

    # Add focus-specific system message if focus is specified
    if @focus && @focus != "web"
      body[:messages].unshift({
        role: "system",
        content: "Focus on #{@focus} content for this search."
      })
    end

    # Add optional parameters that might be required by the API
    body[:temperature] = 0.7 unless body.key?(:temperature)

    body
  end
end
