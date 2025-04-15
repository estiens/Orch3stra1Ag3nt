FactoryBot.define do
  factory :project do
    sequence(:name) { |n| "Test Project #{n}" }
    description { "A test project for specs" }
  end
end
