# frozen_string_literal: true

# Event: Active Record model for storing legacy events and providing backward compatibility
# This model is still used for dashboard broadcasting and historical queries
class Event < ApplicationRecord
  include DashboardBroadcaster
  include Contextable

  # Association with an agent activity - optional for system events
  belongs_to :agent_activity, optional: true
  validates :agent_activity, presence: true, unless: :system_event?

  # Validations
  validates :event_type, presence: true

  # Use Rails 7's serialized_hash attribute for cleaner data handling
  serialize :data, coder: JSON

  # Schema validation
  validate :validate_against_schema, if: -> { event_type.present? }

  # Ensure data is always a hash
  def data
    super || {}
  end

  # Override the setter to ensure data is always properly formatted
  def data=(value)
    super(value.is_a?(Hash) ? value : {})
  end

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

  # Create and publish an event in one step (DEPRECATED)
  # This method now delegates to EventService.publish
  # Use EventService.publish directly instead
  def self.publish(event_type, data = {}, options = {})
    # Convert options to metadata format
    metadata = {}
    metadata[:agent_activity_id] = options[:agent_activity_id] if options[:agent_activity_id]
    metadata[:task_id] = options[:task_id] if options[:task_id]
    metadata[:project_id] = options[:project_id] if options[:project_id]
    metadata[:system_event] = options[:system_event] || false
    
    # Add priority from options if present
    metadata[:priority] = options[:priority] if options[:priority]
    
    # Convert legacy event type to new dot notation format
    event_type = EventMigrationExample.map_legacy_to_new_event_type(event_type)

    # Publish through EventService
    # This will also create a legacy Event record
    EventService.publish(event_type, data, metadata)
  end

  # Process this event through the EventBus
  # This is used for testing and for reprocessing events
  def process
    # For backward compatibility, use the old EventBus
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

  # Get the schema for this event type
  def schema
    EventSchemaRegistry.schema_for(event_type)
  end

  # Check if this event type has a registered schema
  def has_schema?
    EventSchemaRegistry.schema_exists?(event_type)
  end

  # Validate this event against its schema
  def validate_against_schema
    return unless has_schema?

    errors = EventSchemaRegistry.validate_event(self)
    errors.each do |error|
      self.errors.add(:data, error)
    end
  end

  private

  # We no longer need this callback as we publish through EventService directly
  # def publish_to_event_bus
  #   EventBus.publish(self)
  # end
end