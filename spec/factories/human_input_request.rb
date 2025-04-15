FactoryBot.define do
  factory :human_input_request do
    question { "Test question" }
    required { true }
    status { "pending" }
    association :task
    association :agent_activity
  end
end
