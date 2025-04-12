FactoryBot.define do
  factory :llm_call do
    association :agent_activity
    request_payload { "MyText" }
    response_payload { "MyText" }
    duration { 1.5 }
    cost { "9.99" }
  end
end
