require "httparty"
require "json"

class PerplexitySearchTool < BaseTool
  def initialize
    super("perplexity_search", "Search the web using Perplexity AI")
  end
  
  def call(args)
    query = args.is_a?(Hash) ? args[:query] : args
    focus = args.is_a?(Hash) ? args[:focus] || "web" : "web"
    begin
      # Validate the API key
      api_key = ENV["PERPLEXITY_API_KEY"]
      unless api_key
        return { error: "PERPLEXITY_API_KEY environment variable is not set" }
      end

      # Validate the query
      if query.to_s.strip.empty?
        return { error: "Search query cannot be empty" }
      end

      # Validate and normalize focus
      valid_focuses = %w[web academic news writing]
      focus = focus.to_s.downcase
      unless valid_focuses.include?(focus)
        focus = "web"
      end

      # Setup API endpoint and headers
      url = "https://api.perplexity.ai/chat/completions"
      headers = {
        "Authorization" => "Bearer #{api_key}",
        "Content-Type" => "application/json"
      }

      # Prepare the request body
      body = {
        model: "sonar-medium-online",
        messages: [
          {
            role: "system",
            content: "You are a helpful research assistant. Please search the web and provide comprehensive, accurate information."
          },
          {
            role: "user",
            content: query
          }
        ],
        max_tokens: 1024,
        temperature: 0.2,
        options: {
          search_focus: focus
        }
      }

      # Make the API request
      response = HTTParty.post(
        url,
        headers: headers,
        body: body.to_json,
        timeout: 30
      )

      # Handle API response
      if response.success?
        data = JSON.parse(response.body)

        # Format the response
        result = {
          query: query,
          response: data["choices"][0]["message"]["content"],
          focus: focus
        }

        # Add citation information if available
        if data["choices"][0]["message"]["context"] &&
           data["choices"][0]["message"]["context"]["citations"]
          citations = data["choices"][0]["message"]["context"]["citations"]
          result[:citations] = citations.map do |citation|
            {
              title: citation["title"],
              url: citation["url"],
              text: citation["text"]
            }
          end
        end

        result
      else
        # Handle error response
        error_message = begin
                          response.parsed_response.dig("error", "message") || "Error details not available"
                        rescue StandardError
                          "Unknown error"
                        end
        {
          error: "Perplexity API error: #{response.code}",
          message: error_message
        }
      end
    rescue => e
      { error: "Error executing Perplexity search: #{e.message}" }
    end
  end
end
