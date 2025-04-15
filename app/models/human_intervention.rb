# HumanIntervention: Model for tracking human intervention requests
# Used for critical issues that need human attention
class HumanIntervention < ApplicationRecord
  include Contextable
  
  belongs_to :agent_activity, optional: true
  has_one :task, through: :agent_activity

  # Validations
  validates :description, presence: true
  validates :urgency, presence: true
  validates :status, presence: true

  # Urgency levels
  URGENCY_LEVELS = %w[low normal high critical].freeze
  validates :urgency, inclusion: { in: URGENCY_LEVELS }

  # Status states
  STATUS_STATES = %w[pending acknowledged resolved dismissed].freeze
  validates :status, inclusion: { in: STATUS_STATES }

  # Scopes
  scope :pending, -> { where(status: "pending") }
  scope :active, -> { where(status: %w[pending acknowledged]) }
  scope :resolved, -> { where(status: "resolved") }
  scope :dismissed, -> { where(status: "dismissed") }
  scope :critical, -> { where(urgency: "critical") }
  scope :high_priority, -> { where(urgency: %w[high critical]) }
  scope :recent, -> { order(created_at: :desc) }

  # Callback to notify admin systems upon creation
  after_create :notify_admins, if: -> { urgency == "critical" }

  # Mark this intervention as acknowledged by human
  def acknowledge!(user_id = nil)
    update!(
      status: "acknowledged",
      acknowledged_at: Time.current,
      acknowledged_by: user_id
    )

    # Emit event for dashboard updates
    Event.publish(
      "human_intervention_acknowledged",
      {
        intervention_id: id,
        description: description,
        acknowledged_by: user_id
      }
    )
  end

  # Mark this intervention as resolved with optional resolution notes
  def resolve!(resolution, user_id = nil)
    update!(
      status: "resolved",
      resolved_at: Time.current,
      resolution: resolution,
      resolved_by: user_id
    )

    # Emit event for task resumption
    Event.publish(
      "human_intervention_resolved",
      {
        intervention_id: id,
        description: description,
        resolution: resolution,
        resolved_by: user_id
      }
    )

    # Resume any paused tasks
    resume_paused_tasks if task.present?
  end

  # Dismiss intervention as not needed or erroneous
  def dismiss!(reason, user_id = nil)
    update!(
      status: "dismissed",
      dismissed_at: Time.current,
      resolution: reason,
      dismissed_by: user_id
    )

    # Emit event
    Event.publish(
      "human_intervention_dismissed",
      {
        intervention_id: id,
        description: description,
        reason: reason,
        dismissed_by: user_id
      }
    )

    # Resume any paused tasks
    resume_paused_tasks if task.present?
  end

  private

  # Send notifications for critical interventions
  def notify_admins
    # In a real application, this would send emails, Slack messages, etc.
    Rails.logger.warn("CRITICAL INTERVENTION REQUESTED: #{description}")

    # Can be used to add notification logic like:
    # AdminMailer.critical_intervention(self).deliver_later
    # SlackNotifier.notify("#ops-alerts", "Critical intervention needed: #{description}")
  end

  # Resume any tasks that were paused by this intervention
  def resume_paused_tasks
    return unless task&.waiting_on_human?

    # Only resume if this was what caused the task to pause
    if task.metadata&.dig("waiting_for_intervention_id") == id.to_s
      task.activate! if task.may_activate?

      # Emit task resumed event
      Event.publish(
        "task_resumed_from_human_intervention",
        {
          task_id: task.id,
          intervention_id: id
        }
      )
    end
  end
end
