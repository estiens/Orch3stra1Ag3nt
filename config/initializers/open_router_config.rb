# OpenRouter configuration for LangChain integration
require "langchain"

module Langchain
  module LLM
    class OpenRouter < Base
      DEFAULTS = {
        temperature: 0.0,
        chat_model: "openrouter/auto",
        embedding_model: "openrouter/auto"
      }.freeze

      attr_reader :defaults, :client, :last_request_payload

      def initialize(api_key:, default_options: {})
        @api_key = api_key
        @defaults = DEFAULTS.merge(default_options)

        # Initialize parameters
        chat_parameters.update(
          model: { default: @defaults[:chat_model] },
          temperature: { default: @defaults[:temperature] },
          providers: { default: [] },
          transforms: { default: [] },
          extras: { default: {} }
        )
      end

      def chat(params = {})
        parameters = chat_parameters.to_params(params)
        messages = parameters.delete(:messages)

        # Ensure default values for providers, transforms, extras
        parameters[:providers] ||= []
        parameters[:transforms] ||= []
        parameters[:extras] ||= {}

        # Make the API request to OpenRouter
        response = openrouter_request(
          messages,
          model: parameters[:model],
          temperature: parameters[:temperature],
          providers: parameters[:providers],
          transforms: parameters[:transforms],
          extras: parameters[:extras]
        )

        # Return a response object
        OpenRouterResponse.new(response)
      end

      def embed(text:, model: nil)
        raise NotImplementedError, "Open Router does not support embeddings yet"
      end

      private

      def openrouter_request(messages, options = {})
        url = "https://openrouter.ai/api/v1/chat/completions"

        headers = {
          "Content-Type" => "application/json",
          "Authorization" => "Bearer #{@api_key}",
          "HTTP-Referer" => ENV["OPENROUTER_REFERER"] || "https://localhost:3000",
          "X-Title" => ENV["OPENROUTER_SITE_NAME"] || "DoubleAgent"
        }

        payload = {
          model: options[:model],
          messages: messages,
          temperature: options[:temperature] || 0.7
        }

        # Add optional parameters if present
        payload[:providers] = options[:providers] if options[:providers].present?
        payload[:transforms] = options[:transforms] if options[:transforms].present?

        # Add any extra parameters
        if options[:extras].present?
          payload.merge!(options[:extras])
        end

        # Store the request payload for logging purposes
        @last_request_payload = payload.deep_dup

        # Record start time for duration calculation
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        response = HTTParty.post(
          url,
          headers: headers,
          body: payload.to_json
        )

        # Calculate duration
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

        if response.code != 200
          raise "OpenRouter API error: #{response.code} - #{response.body}"
        end

        response_data = JSON.parse(response.body)

        # Enhance the response data with additional metadata
        response_data["_metadata"] = {
          "duration" => duration,
          "request_time" => Time.now.utc
        }

        response_data
      end
    end

    class OpenRouterResponse < BaseResponse
      def model
        raw_response["model"]
      end

      def provider
        # Extract provider from model string if available (e.g., "openai/gpt-4" -> "openai")
        model_str = raw_response["model"].to_s
        if model_str.include?("/")
          provider_name = model_str.split("/").first
          return "OpenAI" if provider_name.downcase == "openai"
          return provider_name
        else
          provider_name = raw_response["provider"] || "openrouter"
          return "OpenAI" if provider_name.downcase == "openai"
          return provider_name
        end
      end

      def chat_completion
        chat_completions.dig(0, "message", "content")
      end

      def chat_completions
        raw_response.dig("choices")
      end

      def tool_calls
        chat_completions.dig(0, "message", "tool_calls") || []
      end

      def role
        raw_response.dig("choices", 0, "message", "role")
      end

      def embedding
        raw_response.dig("data", 0, "embedding")
      end

      def prompt_tokens
        raw_response.dig("usage", "prompt_tokens")
      end

      def total_tokens
        raw_response.dig("usage", "total_tokens")
      end

      def completion_tokens
        raw_response.dig("usage", "completion_tokens")
      end

      def created_at
        if raw_response.dig("created")
          Time.at(raw_response.dig("created"))
        end
      end

      def duration
        raw_response.dig("_metadata", "duration")
      end

      def request_time
        raw_response.dig("_metadata", "request_time")
      end

      def id
        raw_response["id"]
      end

      def finish_reason
        raw_response.dig("choices", 0, "finish_reason")
      end
    end
  end
end

# Don't try to register the class - this method doesn't exist
# Instead, we'll just define the class and use it directly
