# frozen_string_literal: true

# BaseEvent: Base class for all event types in the system
# Provides common functionality and schema validation for events
class BaseEvent < RailsEventStore::Event
  # Schema validation using dry-schema
  # Each event type should define its own schema

  # Class method for defining data schemas
  def self.data_schema(&block)
    if block_given?
      require "dry/schema"
      @schema = Dry::Schema.Params(&block)
    end
    @schema
  end

  # Helper methods for accessing common metadata
  def id
    event_id
  end

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
  # Uses the schema defined by the data_schema class method
  def valid?
    return true unless self.class.data_schema # No schema, no validation needed

    result = self.class.data_schema.call(data)
    @validation_result = result
    result.success?
  end

  # Get validation errors
  # Returns errors from the schema validation
  def validation_errors
    return [] unless @validation_result && @validation_result.failure?

    @validation_result.errors.to_h.map do |key, messages|
      "#{key}: #{messages.join(', ')}"
    end
  end
end
