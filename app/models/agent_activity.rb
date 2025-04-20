class AgentActivity < ApplicationRecord
  include EventPublisher
  include DashboardBroadcaster
  include Contextable

  validates :agent_type, presence: true
  validates :status, presence: true

  belongs_to :task
  has_ancestry

  has_many :llm_calls, dependent: :destroy
  has_many :events, dependent: :destroy

  # Mark this activity as failed with an error message
  def mark_failed(error_message)
    # First update the status and error message
    update(
      status: "failed",
      error_message: error_message
    )

    # Event publishing removed - handled by Task model's TaskFailedEvent
  end

  # Pause this agent activity
  def pause!
    return false if status == "paused"

    update(status: "paused")

    # Event publishing removed - handled by Task model's TaskPausedEvent

    true
  end

  # Resume this agent activity
  def resume!
    return false unless status == "paused"

    update(status: "running")

    # Event publishing removed - handled by Task model's TaskResumedEvent

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
