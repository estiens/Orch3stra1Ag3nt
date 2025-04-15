class LlmCall < ApplicationRecord
  include DashboardBroadcaster if defined?(DashboardBroadcaster)

  belongs_to :agent_activity

  # Validations
  validates :provider, presence: true
  validates :model, presence: true

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :by_model, ->(model) { where(model: model) }
  scope :by_provider, ->(provider) { where(provider: provider) }
  scope :expensive, -> { where("cost > ?", 0.05) }
  scope :large_tokens, -> { where("tokens_used > ?", 2000) }
  scope :in_time_range, ->(start_time, end_time) { where(created_at: start_time..end_time) }

  # Calculate the total cost for a set of LLM calls
  def self.total_cost
    sum(:cost)
  end

  # Calculate the total tokens used for a set of LLM calls
  def self.total_tokens
    sum(:tokens_used)
  end

  # Get a summary of LLM usage by model
  def self.usage_by_model
    group(:model).select("model, COUNT(*) as calls, SUM(tokens_used) as tokens, SUM(cost) as total_cost")
  end

  # Get a summary of LLM usage by provider
  def self.usage_by_provider
    group(:provider).select("provider, COUNT(*) as calls, SUM(tokens_used) as tokens, SUM(cost) as total_cost")
  end

  # Serialize large text fields to avoid DB issues
  before_save :truncate_large_fields

  private

  # Truncate large text fields to prevent DB issues
  def truncate_large_fields
    # Limit prompt and response to 65,000 characters (for MySQL TEXT fields)
    # Adjust limits based on your database type
    max_length = 65_000

    self.prompt = prompt.to_s.truncate(max_length) if prompt.to_s.length > max_length
    self.response = response.to_s.truncate(max_length) if response.to_s.length > max_length

    # Truncate JSON payloads to a reasonable size
    if request_payload.to_s.length > max_length
      self.request_payload = { truncated: true, original_size: request_payload.to_s.length }.to_json
    end

    if response_payload.to_s.length > max_length
      self.response_payload = { truncated: true, original_size: response_payload.to_s.length }.to_json
    end
  end
end
