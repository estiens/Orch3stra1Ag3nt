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
    
    # Health tracking
    @@health_status = {
      consecutive_failures: 0,
      last_failure_time: nil,
      current_batch_size: API_BATCH_SIZE,
      total_requests: 0,
      successful_requests: 0
    }

    attr_reader :api_key, :endpoint, :logger

    def initialize(api_key: nil, endpoint: nil)
      @api_key = api_key || ENV["HUGGINGFACE_API_TOKEN"]
      @endpoint = endpoint || ENV["HUGGINGFACE_EMBEDDING_ENDPOINT"] || DEFAULT_API_ENDPOINT
      @logger = Embedding::Logger.new("ApiClient")

      raise "HUGGINGFACE_API_TOKEN environment variable not set" unless @api_key
    end
    
    # Get current API health status
    def self.health_status
      success_rate = if @@health_status[:total_requests] > 0
                       (@@health_status[:successful_requests].to_f / @@health_status[:total_requests] * 100).round(1)
                     else
                       0.0
                     end
                     
      {
        consecutive_failures: @@health_status[:consecutive_failures],
        last_failure_time: @@health_status[:last_failure_time],
        current_batch_size: @@health_status[:current_batch_size],
        total_requests: @@health_status[:total_requests],
        successful_requests: @@health_status[:successful_requests],
        success_rate: "#{success_rate}%"
      }
    end
    
    # Reset health status (e.g., after service restart)
    def self.reset_health_status
      @@health_status = {
        consecutive_failures: 0,
        last_failure_time: nil,
        current_batch_size: API_BATCH_SIZE,
        total_requests: 0,
        successful_requests: 0
      }
    end
    
    # Get recommended batch size based on health status
    def recommended_batch_size
      # If we've had failures, reduce batch size
      if @@health_status[:consecutive_failures] > 0
        # Reduce batch size based on consecutive failures
        reduced_size = [API_BATCH_SIZE - (@@health_status[:consecutive_failures] * 4), 4].max
        @logger.debug("Using reduced batch size of #{reduced_size} due to #{@@health_status[:consecutive_failures]} consecutive failures")
        reduced_size
      else
        # Use standard batch size
        API_BATCH_SIZE
      end
    end

    # Generate embeddings for a batch of texts
    def generate_batch_embeddings(texts, batch_size: nil)
      return [] if texts.empty?

      # Get health-aware batch size
      health_batch_size = recommended_batch_size
      
      # Use the smaller of requested batch size, health-based size, or API limit
      effective_batch_size = [
        batch_size || API_BATCH_SIZE,
        health_batch_size,
        API_BATCH_SIZE
      ].compact.min

      @logger.debug("API key present? #{@api_key.present?}")
      @logger.debug("Using embedding endpoint: #{@endpoint}")
      @logger.debug("Using batch size: #{effective_batch_size} (health status: #{@@health_status[:consecutive_failures]} failures)")

      # Process in smaller batches if needed
      results = []
      total_batches = (texts.size.to_f / effective_batch_size).ceil
      
      texts.each_slice(effective_batch_size).with_index do |batch, index|
        @logger.debug("Processing batch #{index + 1}/#{total_batches} (#{batch.size} texts)")
        
        # Track request for health monitoring
        @@health_status[:total_requests] += 1
        
        begin
          batch_results = process_embedding_batch(batch)
          
          # Update health status on success
          @@health_status[:consecutive_failures] = 0
          @@health_status[:successful_requests] += 1
          
          results.concat(batch_results)
        rescue => e
          # Update health status on failure
          @@health_status[:consecutive_failures] += 1
          @@health_status[:last_failure_time] = Time.now
          
          @logger.error("Batch #{index + 1}/#{total_batches} failed: #{e.message}")
          
          # Return nil placeholders for this batch
          results.concat(Array.new(batch.size))
        end
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

      # Check for empty strings or nil values
      batch = batch.map { |text| text.to_s.strip.presence || " " }
      
      # Check for very large texts that might cause API issues
      total_chars = batch.sum(&:length)
      if total_chars > 100_000
        @logger.warn("Large batch detected (#{total_chars} chars), may cause API timeout")
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
      http.read_timeout = 300  # 5 minutes
      http.open_timeout = 30
      
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
  end
end
