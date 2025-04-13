# HumanInputRequest: Tracks requests for human input during agent tasks
# Used for both required (task-blocking) and optional (non-blocking) input
class HumanInputRequest < ApplicationRecord
  belongs_to :task
  belongs_to :agent_activity, optional: true

  # Validations
  validates :question, presence: true
  validates :status, presence: true

  # Attributes
  attribute :required, :boolean, default: false

  # Status states
  STATUS_STATES = %w[pending answered ignored expired].freeze
  validates :status, inclusion: { in: STATUS_STATES }

  # Scopes
  scope :pending, -> { where(status: "pending") }
  scope :answered, -> { where(status: "answered") }
  scope :required_inputs, -> { where(required: true) }
  scope :optional_inputs, -> { where(required: false) }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_task, ->(task_id) { where(task_id: task_id) }

  # Callback to set expiration time if provided
  before_create :set_expiry

  # Provide an answer to this input request
  def answer!(response, user_id = nil)
    update!(
      status: "answered",
      response: response,
      answered_at: Time.current,
      answered_by: user_id
    )

    # Emit event about this new answer
    Event.publish(
      "human_input_provided",
      {
        request_id: id,
        task_id: task_id,
        question: question,
        response: response,
        required: required
      }
    )

    # Resume task if it was waiting for this input
    resume_task if required && task.waiting_on_human?
  end

  # Mark this input request as ignored (for optional requests)
  def ignore!(reason = nil, user_id = nil)
    # Only optional inputs can be ignored
    raise "Cannot ignore required input" if required

    update!(
      status: "ignored",
      response: reason,
      answered_at: Time.current,
      answered_by: user_id
    )

    # Emit event
    Event.publish(
      "human_input_ignored",
      {
        request_id: id,
        task_id: task_id,
        question: question,
        reason: reason
      }
    )
  end

  # Check if the request has expired
  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  # Mark as expired if the time limit has passed
  def check_expiration!
    return unless pending? && expired?

    update!(status: "expired")

    # Emit event
    Event.publish(
      "human_input_expired",
      {
        request_id: id,
        task_id: task_id,
        question: question,
        required: required
      }
    )

    # If the input was required, handle the timeout based on configuration
    if required
      handle_expired_required_input
    end
  end

  # Has the request been answered?
  def answered?
    status == "answered"
  end

  # Is the request still pending?
  def pending?
    status == "pending"
  end

  private

  # Set expiry time if timeout is provided
  def set_expiry
    return unless timeout_minutes.present?

    self.expires_at = timeout_minutes.minutes.from_now
  end

  # Resume the task if it was waiting for this input
  def resume_task
    # Only resume if this task was waiting for human input
    return unless task.waiting_on_human?

    # Only resume if this was what caused the task to pause
    # Check if this specific input request was what caused the pause
    if task.metadata&.dig("waiting_for_input_id") == id.to_s
      task.activate! if task.may_activate?

      # Emit task resumed event
      Event.publish(
        "task_resumed_from_human_input",
        {
          task_id: task.id,
          input_request_id: id,
          question: question,
          response: response
        }
      )
    end
  end

  # Handle expiration of required inputs
  def handle_expired_required_input
    # Different strategies can be implemented:
    # 1. Fail the task
    # 2. Escalate to human intervention
    # 3. Use a default/fallback value

    # Default approach: escalate to a human intervention
    HumanIntervention.create!(
      description: "Required input timed out: '#{question}'",
      urgency: "high",
      status: "pending",
      agent_activity: agent_activity
    )

    # Emit task timeout event
    Event.publish(
      "task_input_timeout",
      {
        task_id: task.id,
        input_request_id: id,
        question: question
      },
      priority: Event::HIGH_PRIORITY
    )
  end
end
