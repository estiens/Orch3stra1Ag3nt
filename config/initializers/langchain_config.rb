# Langchain Framework Initialization for Rails

require "langchainrb"

# Ensure OpenRouter API key is present (fail fast if missing)
unless ENV["OPEN_ROUTER_API_KEY"].present?
  Rails.logger.error("OPEN_ROUTER_API_KEY is not set. Langchain agents will not be able to make LLM calls.")
end

# Set up model configurations via Rails.configuration
Rails.application.configure do
  # Model defaults for different agent tasks (customize as necessary)
  config.llm = {
    models: {
      fast: "deepseek/deepseek-chat-v3-0324",
      thinking: "optimus-alpha",
      tools: "deepseek/deepseek-chat-v3-0324",
      web_search: "openai/gpt-4o-mini-search-preview",
      multimodal: "meta-llama/llama-3.2-11b-vision-instruct"
    },
    # Map legacy Regent keys to new config
    regent_to_langchain_map: {
      fast: :fast,
      thinking: :thinking,
      tools: :tools,
      multimodal: :multimodal
    }
  }
end

# Initialize OpenRouter LLM
Rails.logger.info("Langchain initialized with OpenRouter LLM provider and custom model defaults.")
