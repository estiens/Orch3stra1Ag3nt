# Configure Langchain OpenRouter provider
module Langchain
  module LLM
    class OpenRouter
      def initialize(api_key: nil, default_options: {})
        @api_key = api_key || ENV["OPEN_ROUTER_API_KEY"]
        @default_options = default_options || {}
        
        raise "OpenRouter API key is required" unless @api_key
      end
      
      def chat(messages, **options)
        options = @default_options.merge(options)
        model = options[:model] || "deepseek/deepseek-chat-v3-0324"
        temperature = options[:temperature] || 0.3
        
        client = ::OpenRouter::Client.new(access_token: @api_key)
        
        formatted_messages = format_messages(messages)
        
        begin
          response = client.complete(
            formatted_messages,
            model: model,
            extras: {
              temperature: temperature,
              stop: options[:stop] || [],
              **options.except(:model, :temperature, :stop)
            }
          )
          
          content = response.dig("choices", 0, "message", "content")
          
          Langchain::LLM::ChatResponse.new(
            content: content,
            response: response,
            prompt_tokens: response.dig("usage", "prompt_tokens").to_i,
            completion_tokens: response.dig("usage", "completion_tokens").to_i
          )
        rescue => e
          Rails.logger.error("OpenRouter API error: #{e.message}")
          raise e
        end
      end
      
      def complete(prompt, **options)
        messages = [{ role: "user", content: prompt }]
        response = chat(messages, **options)
        
        Langchain::LLM::CompletionResponse.new(
          content: response.content,
          response: response.response,
          prompt_tokens: response.prompt_tokens,
          completion_tokens: response.completion_tokens
        )
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
    
    # Response classes to match Langchain's expected format
    class ChatResponse
      attr_reader :content, :response, :prompt_tokens, :completion_tokens
      
      def initialize(content:, response:, prompt_tokens: 0, completion_tokens: 0)
        @content = content
        @response = response
        @prompt_tokens = prompt_tokens
        @completion_tokens = completion_tokens
      end
    end
    
    class CompletionResponse < ChatResponse
    end
  end
end

# Register the OpenRouter provider with Langchain
Langchain::LLM.register(:openrouter) do |api_key: nil, **options|
  Langchain::LLM::OpenRouter.new(api_key: api_key, default_options: options)
end
