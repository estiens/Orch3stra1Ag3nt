FactoryBot.define do
  factory :llm_call do
    association :agent_activity
    provider { "openrouter" }
    model { "deepseek/deepseek-chat-v3-0324" }
    prompt { "This is a test prompt" }
    response { "This is a test response" }
    tokens_used { 100 }
    created_at { Time.current }
  end
end
