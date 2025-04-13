FactoryBot.define do
  factory :task do
    sequence(:title) { |n| "Test Task #{n}" }
    description { "This is a test task" }
    state { "pending" }

    trait :active do
      state { "active" }
    end

    trait :completed do
      state { "completed" }
    end

    trait :failed do
      state { "failed" }
    end

    trait :waiting_on_human do
      state { "waiting_on_human" }
    end

    factory :task_with_activities do
      transient do
        activities_count { 2 }
      end

      after(:create) do |task, evaluator|
        create_list(:agent_activity, evaluator.activities_count, task: task)
      end
    end
  end
end
