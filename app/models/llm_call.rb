class LlmCall < ApplicationRecord
  include DashboardBroadcaster if defined?(DashboardBroadcaster)
  
  belongs_to :agent_activity
  
  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :by_model, ->(model) { where(model: model) }
  scope :by_provider, ->(provider) { where(provider: provider) }
end
