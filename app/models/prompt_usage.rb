# frozen_string_literal: true

# PromptUsage: Tracks when and how prompts are used
# Helps in analyzing prompt effectiveness and adoption
class PromptUsage < ApplicationRecord
  # Associations
  belongs_to :prompt
  belongs_to :prompt_version, optional: true
  belongs_to :agent_activity, optional: true

  # Validations
  validates :agent_type, presence: true

  # Callbacks
  before_validation :set_prompt_version, if: -> { prompt_version_id.nil? && prompt_id.present? }

  # Scopes
  scope :by_agent_type, ->(agent_type) { where(agent_type: agent_type) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_date_range, ->(start_date, end_date) { where(created_at: start_date..end_date) }

  # Get the LLM response associated with this usage (if available)
  def llm_response
    return nil unless agent_activity

    # Find the LLM call event that happened closest to this usage
    # This is an approximation - a more precise system would directly link usages to LLM calls
    agent_activity.events.where(event_type: "llm_call").order(created_at: :desc).first
  end

  # Determine if the usage was successful based on associated activity
  def successful?
    return false unless agent_activity

    # Consider successful if the agent activity completed successfully
    agent_activity.status == "finished"
  end

  # Get tokens used for this prompt usage (if available)
  def tokens_used
    llm_event = llm_response
    return nil unless llm_event

    # Extract token usage from event data if available
    llm_event.data&.dig("token_usage", "total") ||
      llm_event.data&.dig("token_usage", "completion") ||
      nil
  end

  private

  # Set the prompt version to the current version of the prompt
  def set_prompt_version
    self.prompt_version = prompt.current_version if prompt
  end
end
