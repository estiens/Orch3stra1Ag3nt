# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Embedding
  # Handles API communication for embedding generation
  class ApiClient
    # Constants for API configuration
    DEFAULT_API_ENDPOINT = "https://piujqyd9p0cdbgx1.us-east4.gcp.endpoints.huggingface.cloud"
    API_BATCH_SIZE = 28  # Reduced from 32 to improve performance
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

      # Use the smaller of requested batch size or API limit
      effective_batch_size = [
        batch_size || API_BATCH_SIZE,
        API_BATCH_SIZE
      ].compact.min

      @logger.debug("API key present? #{@api_key.present?}")
      @logger.debug("Using embedding endpoint: #{@endpoint}")
      @logger.debug("Using batch size: #{effective_batch_size}")

      # Process in smaller batches if needed
      results = []
      total_batches = (texts.size.to_f / effective_batch_size).ceil

      # Use a thread pool for parallel processing with controlled concurrency
      pool = Concurrent::ThreadPoolExecutor.new(
        min_threads: 1,
        max_threads: 4, # Limit concurrent API calls
        max_queue: 100,
        fallback_policy: :caller_runs
      )

      mutex = Mutex.new
      futures = []

      texts.each_slice(effective_batch_size).with_index do |batch, index|
        # Submit batch processing to thread pool
        futures << pool.post do
          @logger.debug("Processing batch #{index + 1}/#{total_batches} (#{batch.size} texts)")

          begin
            batch_results = process_embedding_batch(batch)

            # Thread-safe append to results
            mutex.synchronize { results.concat(batch_results) }
          rescue => e
            @logger.error("Batch #{index + 1}/#{total_batches} failed: #{e.message}")

            # Return nil placeholders for this batch
            mutex.synchronize { results.concat(Array.new(batch.size)) }
          end
        end
      end

      # Wait for all batches to complete
      pool.shutdown
      pool.wait_for_termination(300) # 5 minute timeout

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

      # Check for empty strings or nil values
      batch = batch.map { |text| text.to_s.strip.presence || " " }

      # Check for very large texts that might cause API issues
      total_chars = batch.sum(&:length)
      if total_chars > 50_000 # Reduced from 100,000
        @logger.warn("Large batch detected (#{total_chars} chars), may cause API timeout")

        # If batch is too large, split it further
        if batch.size > 1 && total_chars > 80_000
          @logger.info("Batch too large (#{total_chars} chars), splitting into smaller batches")

          # Process each item individually and return combined results
          results = []
          batch.each do |text|
            @logger.debug("Processing individual text (#{text.length} chars)")
            single_result = process_embedding_batch([ text ])
            results.concat(single_result)
          end
          return results
        end
      end

      uri = URI.parse(@endpoint)
      @logger.debug("Creating HTTP request to #{uri}")

      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@api_key}"
      request.content_type = "application/json"
      request["User-Agent"] = "DoubleAgent/1.0"

      request_body = {
        inputs: batch,
        normalize: true
      }
      request.body = request_body.to_json

      @logger.debug("Payload size: #{request.body.bytesize} bytes, #{batch.size} texts")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.read_timeout = 180  # 3 minutes - reduced from 5 minutes
      http.open_timeout = 20   # Reduced from 30

      @logger.debug("Sending embedding request to API")
      start_time = Time.now

      retries = 0
      begin
        response = http.request(request)
        duration = Time.now - start_time

        if response.code == "200"
          @logger.debug("Received successful response in #{duration.round(2)}s (#{response.body.bytesize} bytes)")
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

          # Handle specific error codes
          case response.code
          when "429"
            # Rate limit exceeded
            raise "Rate limit exceeded, backing off"
          when "413"
            # Payload too large
            raise "Payload too large, consider reducing batch size"
          when "504", "502", "503"
            # Gateway timeout or server error
            raise "Server error (#{response.code}), may need to reduce batch size"
          else
            raise "API error: #{response.code} - #{response.body}"
          end
        end
      rescue => e
        retries += 1
        if retries < MAX_RETRIES
          # Exponential backoff with jitter
          backoff = (15 * (2 ** (retries - 1))) + rand(5)
          @logger.warn("API call failed, retrying (#{retries}/#{MAX_RETRIES}) after #{backoff}s: #{e.message}")
          sleep(backoff)
          retry
        else
          @logger.error("Failed to generate embeddings after #{MAX_RETRIES} retries: #{e.message}")
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
      request["User-Agent"] = "DoubleAgent/1.0"
      request.content_type = "application/json"
      request.body = request_body

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.read_timeout = 180  # 3 minutes
      http.open_timeout = 30

      retries = 0
      start_time = Time.now

      begin
        response = http.request(request)
        duration = Time.now - start_time

        if response.code == "200"
          @logger.debug("Single embedding request completed in #{duration.round(2)}s")
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
          @logger.error("API error (#{duration.round(2)}s): #{response.code} - #{response.body}")

          # Handle specific error codes
          case response.code
          when "429"
            raise "Rate limit exceeded"
          when "413"
            raise "Payload too large"
          else
            raise "API error: #{response.code} - #{response.body}"
          end
        end
      rescue => e
        retries += 1
        if retries < MAX_RETRIES
          # Exponential backoff with jitter
          backoff = (10 * (2 ** (retries - 1))) + rand(5)
          @logger.warn("Single API call failed, retrying (#{retries}/#{MAX_RETRIES}) after #{backoff}s: #{e.message}")
          sleep(backoff)
          retry
        else
          @logger.error("Failed single embedding request: #{e.message}")
          raise
        end
      end
    end
    # Test API connection with a simple request
    def test_connection
      @logger.debug("Testing API connection to #{@endpoint}")

      begin
        # Use a very simple text for testing
        result = generate_embedding("test connection")

        if result.is_a?(Array) && result.size > 0
          @logger.debug("API connection test successful - received embedding of size #{result.size}")
          { success: true, embedding_size: result.size }
        else
          @logger.error("API connection test failed - invalid response format")
          { success: false, error: "Invalid response format" }
        end
      rescue => e
        @logger.error("API connection test failed: #{e.message}")
        { success: false, error: e.message }
      end
    end

    # Make test_connection public
    public :test_connection
  end
end
