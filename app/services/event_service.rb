# frozen_string_literal: true

# EventService: Central service for publishing events to the system
# Handles event creation, validation, and publishing to the event store
class EventService
  class << self
    def publish(event_type, data = {}, metadata = {})
      # Convert event_type to an event class
      event_class = event_class_for(event_type)
      return nil unless event_class

      # Create event instance with optional custom event type for GenericEvent
      if event_class == GenericEvent
        event = event_class.new(data: data, metadata: metadata, event_type: event_type)
      else
        event = event_class.new(data: data, metadata: metadata)
      end

      # Validate the event data
      unless event.valid?
        Rails.logger.error("Invalid event data for #{event_type}: #{event.validation_errors}")
        return nil
      end

      # Publish to the event store
      stream_name = stream_for(metadata)
      correlation_id = metadata[:correlation_id] || SecureRandom.uuid
      causation_id = metadata[:causation_id]

      # Enrich metadata
      enriched_metadata = metadata.merge(
        correlation_id: correlation_id,
        timestamp: Time.current
      )

      # Only add causation_id if present
      enriched_metadata[:causation_id] = causation_id if causation_id

      # Create the event with enriched metadata
      if event_class == GenericEvent
        event = event_class.new(data: data, metadata: enriched_metadata, event_type: event_type)
      else
        event = event_class.new(data: data, metadata: enriched_metadata)
      end

      # Publish to Rails Event Store (skip in test environment)
      if defined?(Rails.configuration.event_store) && !Rails.configuration.event_store.nil? && !Rails.env.test?
        Rails.configuration.event_store.publish(
          event,
          stream_name: stream_name
        )
      end


      event
    end

    private

    # Convert event type string to event class
    # Handles both dot notation (tool_execution.started) and snake_case (tool_execution_started)
    def event_class_for(event_type)
      # Convert dots to underscores if needed
      event_type_str = event_type.to_s.gsub(".", "_")

      # Try both potential naming conventions
      namespaced_class_name = "#{event_type_str.camelize}Event"
      module_class_name = if event_type_str.include?("_")
                            prefix, action = event_type_str.split("_", 2)
                            "#{prefix.camelize}Events::#{action.camelize}Event"
      else
                            "#{event_type_str.camelize}Event"
      end

      # Also try with the dots intact for new style events
      dotted_module_name = if event_type.to_s.include?(".")
                             parts = event_type.to_s.split(".")
                             "#{parts.first.camelize}Events::#{parts.last.camelize}Event"
      end

      # Try to find and return the class
      [ namespaced_class_name, module_class_name, dotted_module_name ].compact.each do |class_name|
        begin
          return class_name.constantize
        rescue NameError
          # Class doesn't exist, try the next naming convention
          next
        end
      end

      # If we can't find the class, log an error and create a generic event
      Rails.logger.error("No event class found for #{event_type}, using GenericEvent")
      GenericEvent
    end

    # Determine the stream name based on metadata
    def stream_for(metadata)
      if metadata[:task_id]
        "task-#{metadata[:task_id]}"
      elsif metadata[:agent_activity_id]
        "agent-activity-#{metadata[:agent_activity_id]}"
      elsif metadata[:project_id]
        "project-#{metadata[:project_id]}"
      else
        "all"
      end
    end
  end
end
