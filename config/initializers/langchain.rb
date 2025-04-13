# Configure Langchain OpenRouter provider
module Langchain
  module LLM
    class OpenRouter < Base
      def initialize(api_key: nil, default_options: {})
        @api_key = api_key || ENV["OPEN_ROUTER_API_KEY"]
        @default_options = default_options || {}
        
        raise "OpenRouter API key is required" unless @api_key
      end
      
      def complete(prompt, **options)
        options = @default_options.merge(options)
        model = options[:model] || "deepseek/deepseek-chat-v3-0324"
        temperature = options[:temperature] || 0.3
        
        client = ::OpenRouter::Client.new(access_token: @api_key)
        
        messages = format_messages(prompt)
        
        begin
          response = client.complete(
            messages,
            model: model,
            extras: {
              temperature: temperature,
              stop: options[:stop] || [],
              **options.except(:model, :temperature, :stop)
            }
          )
          
          {
            completion: response.dig("choices", 0, "message", "content"),
            model: model,
            input_tokens: response.dig("usage", "prompt_tokens"),
            output_tokens: response.dig("usage", "completion_tokens")
          }
        rescue => e
          Rails.logger.error("OpenRouter API error: #{e.message}")
          raise e
        end
      end
      
      private
      
      def format_messages(prompt)
        if prompt.is_a?(String)
          [ { role: "user", content: prompt } ]
        elsif prompt.is_a?(Array)
          prompt.map do |message|
            if message.is_a?(Hash)
              { role: message[:role] || "user", content: message[:content] }
            elsif message.is_a?(String)
              { role: "user", content: message }
            end
          end
        else
          raise ArgumentError, "Invalid prompt format. Expected String or Array."
        end
      end
    end
  end
end

# Register the OpenRouter provider
Langchain::LLM.register_provider(:openrouter, Langchain::LLM::OpenRouter)
