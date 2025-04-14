FactoryBot.define do
  factory :project do
    sequence(:name) { |n| "Test Project #{n}" }
    description { "This is a test project" }
    status { "active" }
  end
end
