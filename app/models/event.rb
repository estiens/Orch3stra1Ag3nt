class Event < ApplicationRecord
  include DashboardBroadcaster
  include Contextable

  # Association with an agent activity - optional for system events
  belongs_to :agent_activity, optional: true
  validates :agent_activity, presence: true, unless: :system_event?

  # Validations
  validates :event_type, presence: true

  # Don't validate presence of data since an empty hash is valid
  # validates :data, presence: true

  # Note: We're not using serialize :data, JSON because it's causing errors
  # Instead we'll handle serialization/deserialization manually

  # Use Rails 7's serialized_hash attribute for cleaner data handling
  serialize :data, coder: JSON

  # Ensure data is always a hash
  def data
    super || {}
  end

  # Override the setter to ensure data is always properly formatted
  def data=(value)
    super(value.is_a?(Hash) ? value : {})
  end

  # No need for the ensure_json_data method anymore as the serializer handles it
  # Remove the callback as well

  # Callback to publish the event when created
  after_create :publish_to_event_bus

  # Scopes for querying events
  scope :unprocessed, -> { where(processed_at: nil) }
  scope :processed, -> { where.not(processed_at: nil) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_type, ->(type) { where(event_type: type) }
  scope :system_events, -> { where(agent_activity_id: nil) }
  scope :for_task, ->(task_id) { where(task_id: task_id) }
  scope :for_project, ->(project_id) { where(project_id: project_id) }

  # Event priority levels
  LOW_PRIORITY = 0
  NORMAL_PRIORITY = 10
  HIGH_PRIORITY = 20
  CRITICAL_PRIORITY = 30

  # Create and publish an event in one step
  def self.publish(event_type, data = {}, options = {})
    # Check if this is a system event (specified by a flag)
    is_system_event = options.delete(:system_event) || false

    # Validate agent_activity_id early to provide better error messages
    if options[:agent_activity_id].blank? && !is_system_event
      Rails.logger.warn("Event.publish: Cannot publish event '#{event_type}' without agent_activity_id")
      return nil
    end

    begin
      # Build event attributes
      event_attrs = {
        event_type: event_type,
        data: data,
        priority: options[:priority] || NORMAL_PRIORITY
      }

      # Add context attributes
      event_attrs[:agent_activity_id] = options[:agent_activity_id] unless is_system_event
      event_attrs[:task_id] = options[:task_id] if options[:task_id].present?
      event_attrs[:project_id] = options[:project_id] if options[:project_id].present?

      # For system events, we need to bypass the agent_activity validation
      if is_system_event
        # Create with validation disabled, then manually validate
        event = new(event_attrs)
        event.save(validate: false)

        # Log system event creation
        Rails.logger.info("Created system event: #{event_type} [#{event.id}]")
      else
        # Normal event creation with validations
        event = create!(event_attrs)
      end

      # Event is published through the after_create callback
      event
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("Event.publish: Failed to create event '#{event_type}': #{e.message}")
      nil
    end
  end

  # Process this event through the EventBus
  # This is used for testing and for reprocessing events
  def process
    EventBus.instance.dispatch_event(self)
    mark_processed!
    self
  end

  # Mark the event as processed
  def mark_processed!
    update(processed_at: Time.current)
  end

  # Alias for compatibility with older tests
  def mark_processed
    mark_processed!
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

  # String representation for better debugging
  def to_s
    "Event[#{id}] #{event_type}"
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

  private

  def publish_to_event_bus
    EventBus.publish(self)
  end
end
