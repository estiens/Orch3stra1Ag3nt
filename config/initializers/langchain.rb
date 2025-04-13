# frozen_string_literal: true

module Langchain
  module LLM
    # Base class for LLM providers
    class Base
      def initialize(*)
        # Base initialization
      end
      
      def chat(*)
        raise NotImplementedError, "Subclasses must implement #chat"
      end
      
      def complete(*)
        raise NotImplementedError, "Subclasses must implement #complete"
      end
      
      def embed(*)
        raise NotImplementedError, "Subclasses must implement #embed"
      end
      
      protected
      
      def depends_on(gem_name)
        begin
          require gem_name
        rescue LoadError
          raise "The #{gem_name} gem is required for this provider. Please add it to your Gemfile."
        end
      end
    end
    
    # LLM interface for Open Router APIs: https://openrouter.ai/docs
    class OpenRouter < Base
      DEFAULTS = {
        temperature: 0.0,
        chat_model: "deepseek/deepseek-chat-v3-0324",
        embedding_model: "openrouter/auto"
      }.freeze

      attr_reader :defaults, :client

      def initialize(api_key: nil, default_options: {})
        depends_on "open_router"

        @api_key = api_key || ENV["OPEN_ROUTER_API_KEY"]
        raise "OpenRouter API key is required" unless @api_key
        
        @client = ::OpenRouter::Client.new(access_token: @api_key)
        @defaults = DEFAULTS.merge(default_options)
      end

      def chat(messages, **options)
        options = @defaults.merge(options)
        model = options[:model] || @defaults[:chat_model]
        temperature = options[:temperature] || @defaults[:temperature]
        
        formatted_messages = format_messages(messages)
        
        begin
          response = @client.complete(
            formatted_messages,
            model: model,
            extras: {
              temperature: temperature,
              stop: options[:stop] || [],
              **options.except(:model, :temperature, :stop)
            }
          )
          
          OpenRouterResponse.new(response)
        rescue => e
          Rails.logger.error("OpenRouter API error: #{e.message}")
          raise e
        end
      end
      
      def complete(prompt, **options)
        messages = [{ role: "user", content: prompt }]
        chat(messages, **options)
      end
      
      def embed(text:, model: nil)
        raise NotImplementedError, "OpenRouter does not support embeddings yet"
      end
      
      def models
        @client.models
      end
      
      private
      
      def format_messages(messages)
        if messages.is_a?(String)
          [ { role: "user", content: messages } ]
        elsif messages.is_a?(Array)
          messages.map do |message|
            if message.is_a?(Hash)
              { role: message[:role] || "user", content: message[:content] }
            elsif message.is_a?(String)
              { role: "user", content: message }
            else
              message # Assume it's already properly formatted
            end
          end
        else
          raise ArgumentError, "Invalid messages format. Expected String or Array."
        end
      end
    end
    
    # Response wrapper for OpenRouter API responses
    class OpenRouterResponse
      attr_reader :response, :content, :prompt_tokens, :completion_tokens
      
      def initialize(response)
        @response = response
        @content = response.dig("choices", 0, "message", "content")
        @prompt_tokens = response.dig("usage", "prompt_tokens").to_i
        @completion_tokens = response.dig("usage", "completion_tokens").to_i
      end
      
      def to_s
        content
      end
    end
  end
end

# Register the OpenRouter provider with Langchain
Langchain::LLM.register(:openrouter) do |api_key: nil, **options|
  Langchain::LLM::OpenRouter.new(api_key: api_key, default_options: options)
end
