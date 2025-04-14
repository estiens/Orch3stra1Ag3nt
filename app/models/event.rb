class Event < ApplicationRecord
  include DashboardBroadcaster
  
  # Association with an agent activity - while optional in DB, validate presence
  belongs_to :agent_activity, optional: false
  validates :agent_activity, presence: true

  # Validations
  validates :event_type, presence: true

  # Don't validate presence of data since an empty hash is valid
  # validates :data, presence: true

  # Note: We're not using serialize :data, JSON because it's causing errors
  # Instead we'll handle serialization/deserialization manually

  # Accessors for working with data as a hash
  def data
    return {} if self[:data].blank?

    if self[:data].is_a?(Hash)
      self[:data]
    else
      begin
        JSON.parse(self[:data].to_s)
      rescue
        {}
      end
    end
  end

  # Override the setter to store hashes as JSON strings
  def data=(value)
    value = {} if value.nil?

    if value.is_a?(Hash)
      self[:data] = value.to_json
    else
      self[:data] = value
    end
  end

  # Convert the data hash to a string before saving
  before_save :ensure_json_data

  def ensure_json_data
    if self[:data].blank?
      # Set an empty hash as default
      self[:data] = {}.to_json
    elsif self[:data].is_a?(Hash)
      # Convert hash to properly formatted JSON string
      self[:data] = self[:data].to_json
    elsif self[:data].is_a?(String) && !self[:data].start_with?("{")
      # If it's a string but not JSON formatted, try to parse it and re-serialize it
      begin
        parsed = JSON.parse(self[:data])
        self[:data] = parsed.to_json
      rescue
        # If it can't be parsed, set to empty hash
        self[:data] = {}.to_json
      end
    end
  end

  # Callback to publish the event when created
  after_create :publish_to_event_bus

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

    # Event is published through the after_create callback
    event
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
