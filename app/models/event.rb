class Event < ApplicationRecord
  # Optional association with an agent activity (can be system-wide events)
  belongs_to :agent_activity, optional: true

  # Validations
  validates :event_type, presence: true

  # Store event data as a JSON column
  serialize :data, JSON

  # Scopes for querying events
  scope :unprocessed, -> { where(processed_at: nil) }
  scope :processed, -> { where.not(processed_at: nil) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_type, ->(type) { where(event_type: type) }
  scope :system_events, -> { where(agent_activity_id: nil) }

  # Event priority levels
  LOW_PRIORITY = 0
  NORMAL_PRIORITY = 10
  HIGH_PRIORITY = 20
  CRITICAL_PRIORITY = 30

  # Create and publish an event in one step
  def self.publish(event_type, data = {}, options = {})
    event = create!(
      event_type: event_type,
      data: data,
      agent_activity_id: options[:agent_activity_id],
      priority: options[:priority] || NORMAL_PRIORITY
    )

    # Publish the event through EventBus
    EventBus.publish(event, async: options.fetch(:async, true))

    event
  end

  # Mark the event as processed
  def mark_processed!
    update(processed_at: Time.current)
  end

  # Record a processing attempt, with optional error
  def record_processing_attempt!(error = nil)
    updates = {
      processing_attempts: processing_attempts + 1
    }

    updates[:processing_error] = error.to_s if error.present?

    update(updates)
  end

  # Check if the event has been processed
  def processed?
    processed_at.present?
  end

  # Check if this is a system-wide event (not tied to an agent activity)
  def system_event?
    agent_activity_id.nil?
  end

  # Helper method to spawn an agent in response to an event
  def spawn_agent(agent_class, purpose: nil, options: {})
    # Merge event data into options
    agent_options = {
      event_id: id,
      event_data: data,
      purpose: purpose || "Processing #{event_type} event"
    }.merge(options)

    # Queue the agent job
    agent_class.enqueue("Process event: #{event_type}", agent_options)
  end
end
