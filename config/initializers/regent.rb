# Regent Framework Initialization for Rails

require "regent"
require "open_router"

# Ensure OpenRouter API key is present (fail fast if missing)
unless ENV["OPEN_ROUTER_API_KEY"].present?
  Rails.logger.error("OPEN_ROUTER_API_KEY is not set. Regent agents will not be able to make LLM calls.")
end

# Model defaults for different agent tasks (customize as necessary)
REGENT_MODEL_DEFAULTS = {
  fast:        "deepseek/deepseek-chat-v3-0324",
  thinking:    "optimus-alpha",
  tools: "deepseek/deepseek-chat-v3-0324",
  web_search: "openai/gpt-4o-mini-search-preview",
  multimodal:  "meta-llama/llama-3.2-11b-vision-instruct"
}.freeze

# (No monkey patching of Regent::LLM -- use the default implementation)

Rails.logger.info("Regent initialized with OpenRouter LLM provider and custom model defaults.")

# (Optional) Event bus setup or subscriptions can go here if needed
# Regent::Bus.subscribe("some_event") { |event| ... }
# frozen_string_literal: true
module Regent
  class LLM
    def instantiate_provider
      Regent::LLM::OpenRouter.new(**options.merge(model: model))
    end

    class OpenRouter < Base
      ENV_KEY = "OPEN_ROUTER_API_KEY"

      depends_on "open_router"

      def invoke(messages, **args)
        messages = format_messages(messages)
        begin
        response = client.complete(
          messages,
          model: model,
          extras: {
            temperature: args[:temperature] || 0.5,
            stop: args[:stop] || [],
            **args
          }
        )
        result(
          model: model,
          content: response.dig("choices", 0, "message", "content"),
          input_tokens: response.dig("usage", "prompt_tokens"),
          output_tokens: response.dig("usage", "completion_tokens")
        )
        rescue Faraday::BadRequestError => e
          logger = Rails.logger
          puts e.response.inspect
        end
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
            end
          end
        else
          raise ArgumentError, "Invalid messages format. Expected String or Array."
        end
      end

      def client
        @client ||= ::OpenRouter::Client.new access_token: api_key
      end
    end
  end
end
