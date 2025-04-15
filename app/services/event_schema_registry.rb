# frozen_string_literal: true

# EventSchemaRegistry: Central registry for event schemas and validation
# Provides a way to register, validate and document event schemas
class EventSchemaRegistry
  include Singleton

  # Class methods - delegates to instance
  class << self
    delegate :register_schema, :validate_event, :schema_for, :registered_schemas, 
             :register_standard_schemas, :schema_exists?, to: :instance
  end

  def initialize
    @schemas = {}
    @mutex = Mutex.new
  end

  # Register a new event schema
  # @param event_type [String] the event type this schema applies to
  # @param schema [Hash] the schema definition with required and optional fields
  # @param description [String] human-readable description of this event
  # @return [Boolean] true if registration succeeded
  def register_schema(event_type, schema = {}, description: nil)
    @mutex.synchronize do
      @schemas[event_type.to_s] = {
        required: schema[:required] || [],
        optional: schema[:optional] || [],
        description: description || "No description provided"
      }
    end
    true
  end

  # Check if a schema exists for an event type
  # @param event_type [String] the event type to check
  # @return [Boolean] true if a schema exists
  def schema_exists?(event_type)
    @mutex.synchronize do
      @schemas.key?(event_type.to_s)
    end
  end

  # Get the schema for an event type
  # @param event_type [String] the event type to get the schema for
  # @return [Hash, nil] the schema or nil if not found
  def schema_for(event_type)
    @mutex.synchronize do
      @schemas[event_type.to_s]&.dup
    end
  end

  # Get all registered schemas
  # @return [Hash] all registered schemas
  def registered_schemas
    @mutex.synchronize do
      @schemas.dup
    end
  end

  # Validate an event against its schema
  # @param event [Event] the event to validate
  # @return [Array] array of validation errors, empty if valid
  def validate_event(event)
    event_type = event.event_type
    data = event.data || {}
    
    # If no schema exists, consider it valid but log a warning
    unless schema_exists?(event_type)
      Rails.logger.warn("No schema registered for event type: #{event_type}")
      return []
    end
    
    schema = schema_for(event_type)
    errors = []
    
    # Check required fields
    schema[:required].each do |field|
      if data[field.to_s].nil? && data[field.to_sym].nil?
        errors << "Missing required field: #{field}"
      end
    end
    
    errors
  end

  # Register standard schemas for common events
  # This is now handled in config/initializers/event_registry.rb
  def register_standard_schemas
    Rails.logger.info("Standard schemas are now registered in config/initializers/event_registry.rb")
  end
end
