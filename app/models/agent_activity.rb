class AgentActivity < ApplicationRecord
  include EventPublisher
  
  validates :agent_type, presence: true
  validates :status, presence: true

  belongs_to :task
  has_ancestry

  has_many :llm_calls, dependent: :destroy
  has_many :events, dependent: :destroy

  # Mark this activity as failed with an error message
  def mark_failed(error_message)
    update(
      status: "failed",
      error_message: error_message
    )
    
    # Publish event for agent failure
    publish_event(
      "agent_failed",
      {
        task_id: task_id,
        agent_type: agent_type,
        error_message: error_message
      }
    )
  end
  
  # Helper to create events with proper context
  def create_event(event_type, data = {})
    events.create!(
      event_type: event_type,
      data: data
    )
  end
end
