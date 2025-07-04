# frozen_string_literal: true

# EventPublisher: A concern to standardize publishing events with proper context
# Provides helpers for safely publishing events with context
module EventPublisher
  extend ActiveSupport::Concern

  included do
    include Contextable unless included_modules.include?(Contextable)
  end

  # Publish an event with the current model's context automatically included
  # @param event_type [String] type of event to publish
  # @param data [Hash] event data payload
  # @param options [Hash] additional options (priority, etc)
  # @return [Event] the created event
  def publish_event(event_type, data = {}, options = {})
    # Get context from the current object
    ctx = context || {}

    # Create merged options with context and priority if provided
    merged_options = ctx.dup
    merged_options[:priority] = options[:priority] if options[:priority].present?

    # Override with any explicitly provided options
    merged_options.merge!(options.slice(:agent_activity_id, :task_id, :project_id))

    # Try to get agent_activity_id from the object if not in context
    if merged_options[:agent_activity_id].blank? && respond_to?(:agent_activity) && agent_activity.present?
      merged_options[:agent_activity_id] = agent_activity.id
    end

    # Try to get task_id from the object if not in context
    if merged_options[:task_id].blank? && respond_to?(:task) && task.present?
      merged_options[:task_id] = task.id
    end

    # Try to get project_id from the object if not in context
    if merged_options[:project_id].blank? && respond_to?(:project) && project.present?
      merged_options[:project_id] = project.id
    end

    # Validate that we have an agent_activity_id before attempting to publish
    if merged_options[:agent_activity_id].blank? && !options[:system_event]
      Rails.logger.warn("#{self.class.name}#publish_event: Cannot publish event '#{event_type}' without agent_activity_id")
      return nil
    end

    # Check if schema exists and validate data against it
    if EventSchemaRegistry.schema_exists?(event_type)
      schema = EventSchemaRegistry.schema_for(event_type)

      # Check required fields
      missing_fields = []
      schema[:required].each do |field|
        if data[field.to_s].nil? && data[field.to_sym].nil?
          missing_fields << field
        end
      end

      if missing_fields.any?
        Rails.logger.error("#{self.class.name}#publish_event: Missing required fields for '#{event_type}': #{missing_fields.join(', ')}")
        return nil
      end
    end

    # Convert legacy event type to new dot notation format if needed
    event_type = EventMigrationExample.map_legacy_to_new_event_type(event_type)

    # Publish event through the EventService
    EventService.publish(event_type, data, merged_options)
  end

  # Class-level method for publishing events
  module ClassMethods
    def publish_event(event_type, data = {}, options = {})
      # Convert legacy event type to new dot notation format if needed
      event_type = EventMigrationExample.map_legacy_to_new_event_type(event_type)

      # Delegate to EventService.publish since we don't have instance context
      EventService.publish(event_type, data, options)
    end
  end
end
