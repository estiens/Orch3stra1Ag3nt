FactoryBot.define do
  factory :task do
    title { "Test Task" }
    description { "Test description" }
    state { "pending" }
  end
end
