# HumanInteraction: Consolidated model for tracking human interactions,
# including critical interventions and specific input requests.
class HumanInteraction < ApplicationRecord
  include EventPublisher # Needed for input request events
  include DashboardBroadcaster # Needed for input request events
  include Contextable

  belongs_to :project

  # Interaction Types
  INTERACTION_TYPES = %w[intervention input_request].freeze
  validates :interaction_type, presence: true, inclusion: { in: INTERACTION_TYPES }

  # Validations
  validates :description, presence: true, if: :intervention? # Description primarily for interventions
  validates :question, presence: true, if: :input_request? # Question required for input requests
  validates :urgency, presence: true, if: :intervention? # Urgency only for interventions
  validates :status, presence: true

  # Attributes specific to input_request
  attribute :required, :boolean, default: false

  # Urgency levels (for interventions)
  URGENCY_LEVELS = %w[low normal high critical].freeze
  validates :urgency, inclusion: { in: URGENCY_LEVELS }, allow_nil: true # Allow nil for input_requests

  # Status states - Merging concepts
  # pending: Initial state for both types
  # acknowledged: Intervention acknowledged by human
  # answered: Input request answered by human
  # resolved: Intervention completed/resolved
  # ignored: Optional input request ignored by human
  # dismissed: Intervention dismissed (invalid/not needed)
  # expired: Input request timed out
  STATUS_STATES = %w[pending acknowledged answered resolved ignored dismissed expired].freeze
  validates :status, inclusion: { in: STATUS_STATES }

  # Scopes
  scope :pending, -> { where(status: "pending") }
  scope :interventions, -> { where(interaction_type: "intervention") }
  scope :input_requests, -> { where(interaction_type: "input_request") }
  scope :required_inputs, -> { input_requests.where(required: true) }
  scope :optional_inputs, -> { input_requests.where(required: false) }
  scope :active_interventions, -> { interventions.where(status: %w[pending acknowledged]) }
  scope :resolved_interventions, -> { interventions.where(status: "resolved") }
  scope :dismissed_interventions, -> { interventions.where(status: "dismissed") }
  scope :answered_inputs, -> { input_requests.where(status: "answered") }
  scope :ignored_inputs, -> { input_requests.where(status: "ignored") }
  scope :expired_inputs, -> { input_requests.where(status: "expired") }
  scope :critical, -> { where(urgency: "critical") }
  scope :high_priority, -> { where(urgency: %w[high critical]) }
  scope :recent, -> { order(created_at: :desc) }

  # Callback to notify admin systems upon creation
  after_create :notify_admins, if: :critical_intervention?
  before_create :set_expiry, if: :input_request? # Set expiry only for input requests

  # Add attribute accessor for timeout_minutes (not stored in DB)
  attr_accessor :timeout_minutes

  # --- Type Checkers ---

  def intervention?
    interaction_type == "intervention"
  end

  def input_request?
    interaction_type == "input_request"
  end

  def critical_intervention?
    intervention? && urgency == "critical"
  end

  # --- Status Checkers ---

  def answered?
    status == "answered"
  end

  def pending?
    status == "pending"
  end

  def expired?
    input_request? && expires_at.present? && expires_at <= Time.current
  end

  # --- Actions (Intervention specific) ---

  # Mark this intervention as acknowledged by human
  def acknowledge!(user_id = nil)
    raise "Cannot acknowledge an input request" unless intervention?
    update!(
      status: "acknowledged",
      acknowledged_at: Time.current,
      acknowledged_by: user_id
    )

    # Emit event for dashboard updates
    publish_event( # Use EventPublisher concern method
      "human_interaction_acknowledged", # Renamed event
      {
        interaction_id: id, # Renamed field
        description: description,
        acknowledged_by: user_id
      }
    )
  end

  # Mark this intervention as resolved with optional resolution notes
  def resolve!(resolution, user_id = nil)
    raise "Cannot resolve an input request, use answer!" unless intervention?
    update!(
      status: "resolved",
      resolved_at: Time.current,
      resolution: resolution,
      resolved_by: user_id
    )

    # Emit event for task resumption
    publish_event(
      "human_interaction_resolved", # Renamed event
      {
        interaction_id: id, # Renamed field
        description: description,
        resolution: resolution,
        resolved_by: user_id
      }
    )

    # Resume any paused tasks if this interaction caused a pause
    resume_paused_tasks("intervention", id) if task.present?
  end

  # Dismiss intervention as not needed or erroneous
  def dismiss!(reason, user_id = nil)
    raise "Cannot dismiss an input request, use ignore!" unless intervention?
    update!(
      status: "dismissed",
      dismissed_at: Time.current,
      resolution: reason, # Re-use resolution field for dismiss reason
      dismissed_by: user_id
    )

    # Emit event
    publish_event(
      "human_interaction_dismissed", # Renamed event
      {
        interaction_id: id, # Renamed field
        description: description,
        reason: reason,
        dismissed_by: user_id
      }
    )

    # Resume any paused tasks if this interaction caused a pause
    resume_paused_tasks("intervention", id) if task.present?
  end

  # --- Actions (Input Request specific) ---

  # Provide an answer to this input request
  def answer!(response_text, user_id = nil)
    raise "Cannot answer an intervention" unless input_request?
    update!(
      status: "answered",
      response: response_text,
      responded_at: Time.current,
      answered_by: user_id
    )

    Rails.logger.info "HumanInteraction (Input Request) #{id} answered: status=#{status}, response=#{response ? response[0..20] + '...' : 'nil'}"

    publish_event(
      "human_input_provided", # Keeping original event name for now
      {
        request_id: id,
        task_id: task_id,
        question: question,
        response: response_text,
        required: required
      }
    )

    # Resume task if it was waiting for this input
    resume_paused_tasks("input", id) if required && task&.waiting_on_human?
  end

  # Mark this input request as ignored (for optional requests)
  def ignore!(reason = nil, user_id = nil)
    raise "Cannot ignore an intervention" unless input_request?
    raise "Cannot ignore required input" if required

    update!(
      status: "ignored",
      response: reason, # Re-use response field for ignore reason
      responded_at: Time.current,
      answered_by: user_id # Re-use answered_by for ignored_by
    )

    publish_event(
      "human_input_ignored", # Keeping original event name
      {
        request_id: id,
        task_id: task_id,
        question: question,
        reason: reason
      }
    )
    # Optional inputs don't pause tasks, so no resume needed
  end

  # Mark as expired if the time limit has passed
  def check_expiration!
    return unless input_request? && pending? && expired?

    update!(status: "expired")

    publish_event(
      "human_input_expired", # Keeping original event name
      {
        request_id: id,
        task_id: task_id,
        question: question,
        required: required
      }
    )

    # If the input was required, handle the timeout
    handle_expired_required_input if required
  end

  private

  # Send notifications for critical interventions
  def notify_admins
    # In a real application, this would send emails, Slack messages, etc.
    Rails.logger.warn("CRITICAL INTERVENTION REQUESTED: #{description}")
    # Potentially add: AdminMailer.critical_interaction(self).deliver_later
    # Potentially add: SlackNotifier.notify("#ops-alerts", "Critical interaction needed: #{description} (ID: #{id})")
  end

  # Set expiry time if timeout is provided for input requests
  def set_expiry
    return unless timeout_minutes.present?
    self.expires_at = timeout_minutes.minutes.from_now
  end

  # Resume any tasks that were paused by this interaction (intervention or required input)
  def resume_paused_tasks(waiting_type, interaction_id)
    return unless task&.waiting_on_human?

    waiting_key = "waiting_for_#{waiting_type}_id" # e.g., waiting_for_intervention_id or waiting_for_input_id

    # Only resume if this specific interaction caused the task to pause
    if task.metadata&.dig(waiting_key) == interaction_id.to_s
      task.activate! if task.may_activate?

      # Emit task resumed event
      publish_event(
        "task_resumed_from_human_interaction", # Unified event name
        {
          task_id: task.id,
          interaction_id: interaction_id,
          interaction_type: interaction_type,
          resumed_by_type: waiting_type # Clarify what triggered resume
        }
      )
    end
  end

  # Handle expiration of required inputs
  def handle_expired_required_input
    # Default approach: Update this interaction to become a critical intervention
    # This avoids creating a separate record.
    Rails.logger.warn "Required HumanInteraction (Input Request) #{id} expired. Escalating to intervention."
    update!(
      interaction_type: "intervention",
      description: "Required input timed out: '#{question}'",
      urgency: "critical", # Escalate urgency
      status: "pending" # Reset status to pending intervention
      # Keep existing agent_activity, task association
    )

    # Notify admins now that it's critical
    notify_admins

    # Emit task timeout event (potentially reuse existing one or create new)
    publish_event(
      "task_input_timeout_escalated", # New event name?
      {
        task_id: task.id,
        interaction_id: id, # Use the current interaction ID
        question: question
      }
      # Removed legacy priority option
    )
  end
end
