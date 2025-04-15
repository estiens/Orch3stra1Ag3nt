# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Embedding
  # Handles API communication for embedding generation
  class ApiClient
    # Constants for API configuration
    DEFAULT_API_ENDPOINT = "https://piujqyd9p0cdbgx1.us-east4.gcp.endpoints.huggingface.cloud"
    API_BATCH_SIZE = 32  # Maximum allowed by the API
    MAX_RETRIES = 3

    attr_reader :api_key, :endpoint, :logger

    def initialize(api_key: nil, endpoint: nil)
      @api_key = api_key || ENV["HUGGINGFACE_API_TOKEN"]
      @endpoint = endpoint || ENV["HUGGINGFACE_EMBEDDING_ENDPOINT"] || DEFAULT_API_ENDPOINT
      @logger = Embedding::Logger.new("ApiClient")

      raise "HUGGINGFACE_API_TOKEN environment variable not set" unless @api_key
    end

    # Generate embeddings for a batch of texts
    def generate_batch_embeddings(texts, batch_size: nil)
      return [] if texts.empty?

      # Ensure we never exceed the API's maximum batch size
      effective_batch_size = [ batch_size || API_BATCH_SIZE, API_BATCH_SIZE ].min

      @logger.debug("API key present? #{@api_key.present?}")
      @logger.debug("Using embedding endpoint: #{@endpoint}")

      # Process in smaller batches if needed
      results = []
      texts.each_slice(effective_batch_size) do |batch|
        batch_results = process_embedding_batch(batch)
        results.concat(batch_results)
      end

      results
    end

    # Generate embedding for a single text
    def generate_embedding(text)
      embedding = make_api_request(@endpoint, @api_key, { inputs: text.to_s, normalize: true }.to_json)

      # Handle nested array format (API sometimes returns [[float, float, ...]])
      if embedding.is_a?(Array) && embedding.size == 1 && embedding.first.is_a?(Array)
        embedding = embedding.first
      end

      embedding
    end

    private

    # Process a batch of texts for embedding
    def process_embedding_batch(batch)
      # Safety check - ensure batch size doesn't exceed API limit
      if batch.size > API_BATCH_SIZE
        @logger.warn("Batch size #{batch.size} exceeds API limit of #{API_BATCH_SIZE}, truncating")
        batch = batch.take(API_BATCH_SIZE)
      end

      uri = URI.parse(@endpoint)
      @logger.debug("Creating HTTP request to #{uri}")
      
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@api_key}"
      request.content_type = "application/json"

      request_body = {
        inputs: batch.map(&:to_s),
        normalize: true
      }
      request.body = request_body.to_json
      
      @logger.debug("Payload size: #{request.body.bytesize} bytes, #{batch.size} texts")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.read_timeout = 300  # 5 minutes
      http.open_timeout = 30
      
      @logger.debug("Sending embedding request to API")

      retries = 0
      begin
        response = http.request(request)
        
        if response.code == "200"
          @logger.debug("Received successful response (#{response.body.bytesize} bytes)")
          batch_results = JSON.parse(response.body)
          
          if batch_results.is_a?(Array) && batch_results.length == batch.size
            @logger.debug("Successfully parsed response - received #{batch_results.length} embeddings")
            batch_results
          else
            @logger.error("Response format error: expected array of #{batch.size} embeddings, got #{batch_results.class}")
            raise "Invalid response format"
          end
        else
          @logger.error("API error: #{response.code} - #{response.body}")
          raise "TEI API error: #{response.code} - #{response.body}"
        end
      rescue => e
        retries += 1
        if retries < MAX_RETRIES
          backoff = 15 * retries
          @logger.warn("API call failed, retrying (#{retries}/#{MAX_RETRIES}) after #{backoff}s: #{e.message}")
          sleep(backoff)
          retry
        else
          @logger.error("Failed to generate embeddings after #{MAX_RETRIES} retries: #{e.message}\n#{e.backtrace.join("\n")}")
          # Return nil placeholders to maintain array positions
          Array.new(batch.size)
        end
      end
    end

    # Make API request with retries
    def make_api_request(endpoint, api_key, request_body)
      uri = URI.parse(endpoint)
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{api_key}"
      request.content_type = "application/json"
      request.body = request_body

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.read_timeout = 180  # 3 minutes
      http.open_timeout = 30
      
      retries = 0
      begin
        response = http.request(request)
        if response.code == "200"
          result = JSON.parse(response.body)

          # Handle different API response formats
          if result.is_a?(Array)
            # Return as is - we'll handle the nested array in the generate_embedding method
            result
          elsif result.is_a?(Hash) && result["embedding"]
            result["embedding"]
          else
            @logger.error("Unexpected embedding format: #{result.class}")
            raise "Unexpected embedding format from API"
          end
        else
          raise "Hugging Face API error: #{response.code} - #{response.body}"
        end
      rescue => e
        retries += 1
        if retries < MAX_RETRIES
          sleep(retries * 10) # Exponential backoff
          retry
        else
          @logger.error("Failed HF embed: #{e.message}")
          raise
        end
      end
    end
  end
end
