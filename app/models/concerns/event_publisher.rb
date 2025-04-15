# frozen_string_literal: true

# EventPublisher: A concern to standardize publishing events with proper context
# Provides helpers for safely publishing events with agent_activity_id
module EventPublisher
  extend ActiveSupport::Concern

  # Publish an event with the current model's agent_activity_id automatically included
  # @param event_type [String] type of event to publish
  # @param data [Hash] event data payload
  # @param options [Hash] additional options (priority, etc)
  # @return [Event] the created event
  def publish_event(event_type, data = {}, options = {})
    # Merge agent_activity_id if it's defined on this model or provided
    activity_id = if respond_to?(:agent_activity_id) && agent_activity_id.present?
                     agent_activity_id
    elsif respond_to?(:agent_activity) && agent_activity&.id.present?
                     agent_activity.id
    else
                     options[:agent_activity_id]
    end

    # Create merged options with activity_id and priority if provided
    merged_options = { agent_activity_id: activity_id }
    merged_options[:priority] = options[:priority] if options[:priority].present?

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
