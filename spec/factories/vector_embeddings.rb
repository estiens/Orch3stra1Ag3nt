FactoryBot.define do
  factory :vector_embedding do
    sequence(:content) { |n| "Sample content for vector embedding #{n}" }
    content_type { "text" }
    collection { "default" }
    embedding { Array.new(384) { rand } } # Default embedding size
    metadata { { embedding_model: "test-model" } }
    
    trait :with_project do
      association :project
    end
    
    trait :with_task do
      association :task
    end
  end
end
