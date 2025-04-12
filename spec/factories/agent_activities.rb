FactoryBot.define do
  factory :agent_activity do
    association :task
    parent { nil }
    agent_type { "GenericAgent" }
    status { "pending" }
  end
end
