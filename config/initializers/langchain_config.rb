# Langchain Framework Initialization for Rails

require "langchainrb"

# Ensure OpenRouter API key is present (fail fast if missing)
unless ENV["OPEN_ROUTER_API_KEY"].present?
  Rails.logger.error("OPEN_ROUTER_API_KEY is not set. Langchain agents will not be able to make LLM calls.")
end

# Model defaults for different agent tasks (customize as necessary)
LANGCHAIN_MODEL_DEFAULTS = {
  fast:        "deepseek/deepseek-chat-v3-0324",
  thinking:    "optimus-alpha",
  tools:       "deepseek/deepseek-chat-v3-0324",
  web_search:  "openai/gpt-4o-mini-search-preview",
  multimodal:  "meta-llama/llama-3.2-11b-vision-instruct"
}.freeze

# Configure Langchain with OpenRouter
Langchainrb.configure do |config|
  config.llm = {
    provider: :openrouter,
    api_key: ENV["OPEN_ROUTER_API_KEY"],
    default_options: {
      model: "deepseek/deepseek-chat-v3-0324",
      temperature: 0.3
    }
  }
end

Rails.logger.info("Langchain initialized with OpenRouter LLM provider and custom model defaults.")
