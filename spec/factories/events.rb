FactoryBot.define do
  factory :event do
    association :agent_activity
    event_type { "MyString" }
    data { "MyText" }
    occurred_at { "2025-04-12 16:35:46" }
  end
end
