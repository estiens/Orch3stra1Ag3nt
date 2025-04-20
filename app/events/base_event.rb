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
end
