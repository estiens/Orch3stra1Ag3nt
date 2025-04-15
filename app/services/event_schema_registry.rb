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
  def register_standard_schemas
    # System events
    register_schema(
      "system.startup",
      { required: ["version", "environment"], optional: ["config"] },
      description: "System startup event with version and environment information"
    )
    
    register_schema(
      "system.shutdown",
      { required: ["reason"], optional: ["exit_code"] },
      description: "System shutdown event with reason"
    )
    
    # Agent events
    register_schema(
      "agent_activity.created",
      { required: ["agent_type", "purpose"], optional: ["options"] },
      description: "Agent activity created"
    )
    
    register_schema(
      "agent_activity.completed",
      { required: ["result"], optional: ["duration", "metrics"] },
      description: "Agent activity completed successfully"
    )
    
    register_schema(
      "agent_activity.failed",
      { required: ["error"], optional: ["stack_trace", "duration"] },
      description: "Agent activity failed with error"
    )
    
    # Task events
    register_schema(
      "task.created",
      { required: ["title", "description"], optional: ["dependencies", "priority"] },
      description: "Task created"
    )
    
    register_schema(
      "task.activated",
      { required: ["task_id"], optional: ["activated_by"] },
      description: "Task activated and ready for processing"
    )
    
    register_schema(
      "task.completed",
      { required: ["task_id"], optional: ["result", "duration"] },
      description: "Task completed successfully"
    )
    
    register_schema(
      "task.failed",
      { required: ["task_id", "error"], optional: ["stack_trace"] },
      description: "Task failed with error"
    )
    
    # Tool events
    register_schema(
      "tool_execution.started",
      { required: ["tool_name", "args"], optional: ["context"] },
      description: "Tool execution started"
    )
    
    register_schema(
      "tool_execution.finished",
      { required: ["tool_name", "result"], optional: ["duration", "metrics"] },
      description: "Tool execution finished successfully"
    )
    
    register_schema(
      "tool_execution.error",
      { required: ["tool_name", "error"], optional: ["args", "stack_trace"] },
      description: "Tool execution failed with error"
    )
    
    # Human interaction events
    register_schema(
      "human_input.requested",
      { required: ["prompt", "request_type"], optional: ["options", "timeout"] },
      description: "Human input requested"
    )
    
    register_schema(
      "human_input.provided",
      { required: ["input", "request_id"], optional: ["metadata"] },
      description: "Human input provided"
    )
    
    # LLM events
    register_schema(
      "llm_call.started",
      { required: ["model", "prompt"], optional: ["options"] },
      description: "LLM call started"
    )
    
    register_schema(
      "llm_call.completed",
      { 
        required: ["model", "response"], 
        optional: ["tokens", "duration", "prompt_tokens", "completion_tokens"] 
      },
      description: "LLM call completed successfully"
    )
    
    # Project events
    register_schema(
      "project.created",
      { required: ["title", "description"], optional: ["metadata"] },
      description: "Project created"
    )
    
    register_schema(
      "project.completed",
      { required: ["project_id"], optional: ["summary", "metrics"] },
      description: "Project completed"
    )
  end
end
