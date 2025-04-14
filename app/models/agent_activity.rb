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
  
  # Pause this agent activity
  def pause!
    return false if status == "paused"
    
    update(status: "paused")
    
    # Publish event for agent paused
    publish_event(
      "agent_paused",
      {
        task_id: task_id,
        agent_type: agent_type
      }
    )
    
    true
  end
  
  # Resume this agent activity
  def resume!
    return false unless status == "paused"
    
    update(status: "running")
    
    # Publish event for agent resumed
    publish_event(
      "agent_resumed",
      {
        task_id: task_id,
        agent_type: agent_type
      }
    )
    
    true
  end
  
  # Helper to create events with proper context
  def create_event(event_type, data = {})
    events.create!(
      event_type: event_type,
      data: data
    )
  end
end
