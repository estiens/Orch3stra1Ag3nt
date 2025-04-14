FactoryBot.define do
  factory :human_intervention do
    description { "Test intervention" }
    urgency { "normal" }
    status { "pending" }
    association :agent_activity
  end
end
