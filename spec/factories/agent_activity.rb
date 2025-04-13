FactoryBot.define do
  factory :agent_activity do
    association :task
    sequence(:agent_type) { |n| "TestAgent#{n}" }
    status { "active" }

    trait :completed do
      status { "completed" }
      completed_at { Time.current }
      result { "result" }
    end

    trait :failed do
      status { "failed" }
      completed_at { Time.current }
      error_message { "error" }
    end

    trait :with_parent do
      parent { create(:agent_activity) }
    end

    trait :with_llm_calls do
      transient do
        llm_calls_count { 2 }
      end

      after(:create) do |activity, evaluator|
        create_list(:llm_call, evaluator.llm_calls_count, agent_activity: activity)
      end
    end

    trait :with_events do
      transient do
        events_count { 2 }
      end

      after(:create) do |activity, evaluator|
        create_list(:event, evaluator.events_count, agent_activity: activity)
      end
    end
  end
end
