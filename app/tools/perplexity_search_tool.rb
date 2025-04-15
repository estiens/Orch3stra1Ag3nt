require "httparty"
require "json"
require "uri"
require "net/http"

class PerplexitySearchTool
  extend Langchain::ToolDefinition

  # One main function, flexible by 'complexity'
  define_function :search, description: "Search or research the web using Perplexity AI. Selects the best model for the requested complexity or mode." do
    property :query, type: "string", description: "The search or research query", required: true
    property :complexity, type: "string", description: "Complexity of the query: 'basic', 'fast_reasoning', 'pro_reasoning', 'deep_research', or leave blank for 'hard' (default: hard)", required: false
    property :focus, type: "string", description: "Search focus (web, academic, news, writing)", required: false
    property :temperature, type: "number", description: "Temperature (0.0-1.0)", required: false
    property :return_images, type: "boolean", description: "Return images in response", required: false
    property :return_related_questions, type: "boolean", description: "Return related questions", required: false
    property :search_context_size, type: "string", description: "Search context (small, medium, large)", required: false
    property :stream, type: "boolean", description: "Stream the response", required: false
  end

  MODEL_MAP = {
    "basic" => "sonar",
    "fast_reasoning" => "sonar-reasoning",
    "pro_reasoning" => "sonar-reasoning-pro",
    "deep_research" => "sonar-deep-research",
    "hard" => "sonar-pro", # default/fallback
    nil => "sonar-pro"
  }
  VALID_COMPLEXITIES = MODEL_MAP.keys

  def initialize
    @api_key = ENV.fetch("PERPLEXITY_API_KEY", nil)
    raise "PERPLEXITY_API_KEY is not set cannot use PerplexitySearchTool" unless @api_key
  end

  # The main interface
  def search(
    query:,
    complexity: nil, # "basic", "fast_reasoning", "pro_reasoning", "deep_research", or blank (default: hard)
    focus: "web",
    temperature: nil,
    return_images: nil,
    return_related_questions: nil,
    search_context_size: nil,
    stream: nil
  )
    model = MODEL_MAP[complexity&.to_s&.downcase] || MODEL_MAP[nil]
    perform_search(
      query: query,
      focus: focus,
      model: model,
      temperature: temperature,
      return_images: return_images,
      return_related_questions: return_related_questions,
      search_context_size: search_context_size,
      stream: stream
    )
  end

  def call(query:, **kwargs)
    search(query: query, **kwargs)
  end

  # Main method, untouched (except with model parameter passed in)
  def perform_search(
    query:, focus: "web", model: "sonar-pro", temperature: nil,
    return_images: nil, return_related_questions: nil,
    search_context_size: nil, stream: nil
  )
    @query = query
    @focus = validate_focus(focus)
    @model = model
    @temperature = temperature
    @return_images = return_images
    @return_related_questions = return_related_questions
    @search_context_size = search_context_size
    @stream = stream

    begin
      Rails.logger.info("Perplexity API request to: #{base_url}")
      Rails.logger.info("Perplexity API headers: #{headers.to_json}")
      Rails.logger.info("Perplexity API request body: #{request_body.to_json}")

      timeout_seconds = [ "sonar-pro", "sonar-deep-research" ].include?(@model) ? 600 : 180
      Rails.logger.info("Using timeout of #{timeout_seconds} seconds for model #{@model}")

      if @stream
        return handle_streaming_request(timeout_seconds)
      else
        response = HTTParty.post(
          base_url,
          headers: headers,
          body: request_body.to_json,
          timeout: timeout_seconds
        )
      end

      if response.success?
        data = JSON.parse(response.body)
        result = {
          query: @query,
          response: data.dig("choices", 0, "message", "content"),
          focus: @focus,
          model: @model
        }
        # All the attachments, citations, related questions, etc, as in your original code...
        result[:citations] = (data["citations"] || []).map { |citation|
          {
            title: citation.split("/").last.to_s.gsub("-", " ").capitalize,
            url: citation
          }
        } if data["citations"]
        result[:images] = (data["images"] || []).map { |image|
          {
            url: image["image_url"],
            origin_url: image["origin_url"],
            height: image["height"],
            width: image["width"]
          }
        } if data["images"]
        result[:related_questions] = data["related_questions"] if data["related_questions"]
        result[:usage] = data["usage"] if data["usage"]
        result[:id] = data["id"] if data["id"]
        result[:created] = data["created"] if data["created"]
        result
      else
        begin
          error_data = JSON.parse(response.body)
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
  # Handle streaming requests using Net::HTTP
  def handle_streaming_request(timeout_seconds)
    uri = URI.parse(base_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.read_timeout = timeout_seconds
    http.open_timeout = 30

    request = Net::HTTP::Post.new(uri.request_uri)
    headers.each { |key, value| request[key] = value }
    request.body = request_body.to_json

    Rails.logger.info("Starting streaming request to Perplexity API")

    # Initialize variables to store the response
    full_response = ""
    chunks = []
    response_data = {}

    begin
      http.request(request) do |response|
        if response.code.to_i >= 400
          # Handle error response
          error_data = JSON.parse(response.body)
          error_message = error_data.dig("error", "message") ||
                         error_data["error"] ||
                         error_data["message"] ||
                         "Error details not available"

          Rails.logger.error("Perplexity API streaming error: #{response.code} - #{error_message}")
          return "No search results found. The search API returned an error: #{error_message}. Please try a different search query or try again later."
        end

        # Process the streaming response
        response.read_body do |chunk|
          # Skip empty chunks
          next if chunk.strip.empty?

          # Log the chunk for debugging
          Rails.logger.debug("Received chunk: #{chunk}")

          # Parse the chunk if it's JSON
          begin
            # Handle SSE format (data: {...})
            if chunk.start_with?("data: ")
              chunk = chunk.sub(/^data: /, "").strip
              # Skip "data: [DONE]" message
              next if chunk == "[DONE]"
            end

            # Parse the JSON chunk
            chunk_data = JSON.parse(chunk)
            chunks << chunk_data

            # Extract content from the chunk if available
            if chunk_data.dig("choices", 0, "delta", "content")
              content = chunk_data.dig("choices", 0, "delta", "content")
              full_response += content

              # Log progress
              if full_response.length % 100 == 0
                Rails.logger.info("Streaming progress: #{full_response.length} characters received")
              end
            end

            # Collect metadata from the chunk
            if chunk_data["id"] && !response_data["id"]
              response_data["id"] = chunk_data["id"]
            end

            if chunk_data["model"] && !response_data["model"]
              response_data["model"] = chunk_data["model"]
            end

            if chunk_data["usage"]
              response_data["usage"] = chunk_data["usage"]
            end

            if chunk_data["citations"]
              response_data["citations"] ||= []
              response_data["citations"] += chunk_data["citations"]
            end

            if chunk_data["images"]
              response_data["images"] ||= []
              response_data["images"] += chunk_data["images"]
            end

            if chunk_data["related_questions"]
              response_data["related_questions"] ||= []
              response_data["related_questions"] += chunk_data["related_questions"]
            end
          rescue JSON::ParserError => e
            Rails.logger.warn("Failed to parse chunk as JSON: #{e.message}")
            # Continue processing the next chunk
          end
        end
      end

      # Format the final response
      result = {
        query: @query,
        response: full_response,
        focus: @focus,
        model: @model,
        streaming: true
      }

      # Add citation information if available
      if response_data["citations"]
        result[:citations] = response_data["citations"].map do |citation|
          {
            title: citation.split("/").last.to_s.gsub("-", " ").capitalize,
            url: citation
          }
        end
      end

      # Add images if available
      if response_data["images"] && !response_data["images"].empty?
        result[:images] = response_data["images"].map do |image|
          {
            url: image["image_url"],
            origin_url: image["origin_url"],
            height: image["height"],
            width: image["width"]
          }
        end
      end

      # Add related questions if available
      if response_data["related_questions"] && !response_data["related_questions"].empty?
        result[:related_questions] = response_data["related_questions"]
      end

      # Add any other metadata from the response
      result[:usage] = response_data["usage"] if response_data["usage"]
      result[:id] = response_data["id"] if response_data["id"]

      Rails.logger.info("Streaming request completed. Total response length: #{full_response.length} characters")

      result
    rescue => e
      Rails.logger.error("Error during streaming request: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      "No search results found due to a streaming error: #{e.message}. Please try again later."
    end
  end

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
      model: @model || "sonar-pro", # Use the specified model or default to sonar-pro
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

    # Add all optional parameters based on the curl example
    body[:temperature] = @temperature || 0.7
    body[:top_p] = 0.9
    body[:top_k] = 0
    body[:stream] = @stream.nil? ? false : @stream # Use provided stream value or default to false
    body[:presence_penalty] = 0
    body[:frequency_penalty] = 1

    # Add image and related questions flags if specified
    body[:return_images] = @return_images unless @return_images.nil?
    body[:return_related_questions] = @return_related_questions unless @return_related_questions.nil?

    # Add web search options if search_context_size is specified
    if @search_context_size
      body[:web_search_options] = {
        search_context_size: @search_context_size
      }
    end

    body
  end
end
