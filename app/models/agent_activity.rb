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

    # Then try to publish the event, with error handling
    begin
      # Publish event for agent failure
      publish_event(
        "agent_failed",
        {
          task_id: task_id,
          agent_type: agent_type,
          error_message: error_message,
          agent_activity_id: id
        }
      )
    rescue => e
      # Log the error but don't raise it, as this is already part of error handling
      Rails.logger.error("[AgentActivity#mark_failed] Failed to publish agent_failed event: #{e.message}")
    end
  end

  # Pause this agent activity
  def pause!
    return false if status == "paused"

    update(status: "paused")

    # Publish event for agent paused with error handling
    begin
      publish_event(
        "agent_paused",
        {
          task_id: task_id,
          agent_type: agent_type,
          agent_activity_id: id
        }
      )
    rescue => e
      # Log the error but don't raise it
      Rails.logger.error("[AgentActivity#pause!] Failed to publish agent_paused event: #{e.message}")
    end

    true
  end

  # Resume this agent activity
  def resume!
    return false unless status == "paused"

    update(status: "running")

    # Publish event for agent resumed with error handling
    begin
      publish_event(
        "agent_resumed",
        {
          task_id: task_id,
          agent_type: agent_type,
          agent_activity_id: id
        }
      )
    rescue => e
      # Log the error but don't raise it
      Rails.logger.error("[AgentActivity#resume!] Failed to publish agent_resumed event: #{e.message}")
    end

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
