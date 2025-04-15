FactoryBot.define do
  factory :task do
    sequence(:title) { |n| "Test Task #{n}" }
    description { "A test task for specs" }
    state { "pending" }
    association :project
  end
end
