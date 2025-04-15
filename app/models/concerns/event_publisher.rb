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
    ctx = context

    # Create merged options with context and priority if provided
    merged_options = ctx
    merged_options[:priority] = options[:priority] if options[:priority].present?
    
    # Override with any explicitly provided options
    merged_options.merge!(options.slice(:agent_activity_id, :task_id, :project_id))

    # Validate that we have an agent_activity_id before attempting to publish
    if merged_options[:agent_activity_id].blank?
      Rails.logger.warn("#{self.class.name}#publish_event: Cannot publish event '#{event_type}' without agent_activity_id")
      return nil
    end

    # Publish event through the EventBus
    Event.publish(event_type, data, merged_options)
  end

  # Class-level method for publishing events
  module ClassMethods
    def publish_event(event_type, data = {}, options = {})
      # Just delegate to Event.publish since we don't have instance context
      Event.publish(event_type, data, options)
    end
  end
end
