# frozen_string_literal: true

# BaseEvent: Base class for all event types in the system
# Provides common functionality and schema validation for events
class BaseEvent < RailsEventStore::Event
  # Schema validation using dry-schema
  # Each event type should define its own schema
  
  # Helper methods for accessing common metadata
  def task_id
    metadata.fetch(:task_id, nil)
  end
  
  def agent_activity_id
    metadata.fetch(:agent_activity_id, nil)
  end
  
  def project_id
    metadata.fetch(:project_id, nil)
  end
  
  # Validate event data against schema
  # Override in subclasses to implement specific validation logic
  def valid?
    true # Base validation always passes
  end
  
  # Get validation errors
  # Override in subclasses to provide specific error messages
  def validation_errors
    []
  end
  
  # Creates an Event record for backward compatibility and dashboard updates
  # This ensures existing functionality continues to work while we transition
  # This method can be disabled by setting Rails.configuration.create_event_records = false
  def create_legacy_event_record
    # Skip in test environment unless explicitly enabled
    return true if Rails.env.test? && !explicitly_create_records?
    
    # Skip if event records are disabled in the configuration
    return true if Rails.configuration.respond_to?(:create_event_records) && 
                   Rails.configuration.create_event_records == false
    
    # Create the legacy event record
    Event.create!(
      event_type: event_type,
      data: data,
      agent_activity_id: agent_activity_id,
      task_id: task_id,
      project_id: project_id
    )
  end
  
  # For testing - allows explicitly setting the create records behavior
  def create_records_override=(value)
    @create_records_override = value
  end
  
  private
  
  # Helper to check if we should create records in test environment
  def explicitly_create_records?
    # Allow this behavior to be stubbed in tests
    return @create_records_override unless @create_records_override.nil?
    
    # In normal operation, check Rails.configuration
    Rails.configuration.respond_to?(:create_event_records) && 
      Rails.configuration.create_event_records == true
  end
end