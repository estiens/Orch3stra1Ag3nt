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

  def search(query:, focus: "web")
    @query = query
    @focus = validate_focus(focus)

    begin
      response = HTTParty.post(
        base_url,
        headers: headers,
        body: request_body.to_json,
        timeout: 30
      )

      # Handle API response
      if response.success?
        data = JSON.parse(response.body)

        # Format the response
        result = {
          query: @query,
          response: data["choices"][0]["message"]["content"],
          focus: @focus
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
    "https://api.perplexity.ai/chat/completions"
  end

  def headers
    {
      "Authorization" => "Bearer #{@api_key}",
      "Content-Type" => "application/json"
    }
  end

  def request_body
    {
      model: "sonar-medium-online",
      messages: [
        {
          role: "system",
          content: "You are a helpful research assistant. Please search the web and provide comprehensive, accurate information."
        },
        {
          role: "user",
          content: @query
        }
      ],
      max_tokens: 1024,
      temperature: 0.2,
      options: {
        search_focus: @focus
      }
    }
  end
end
