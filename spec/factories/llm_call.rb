FactoryBot.define do
  factory :llm_call do
    association :agent_activity
    provider { "openrouter" }
    model { "deepseek/deepseek-chat-v3-0324" }
    prompt { "This is a test prompt" }
    response { "This is a test response" }
    tokens_used { 100 }
    prompt_tokens { 50 }
    completion_tokens { 50 }
    request_payload { { model: "deepseek/deepseek-chat-v3-0324", messages: [ { role: "user", content: "This is a test prompt" } ] }.to_json }
    response_payload { { id: "gen-123456", choices: [ { message: { content: "This is a test response" } } ] }.to_json }
    duration { 0.5 }
    cost { 0.0025 }
    created_at { Time.current }
  end
end
