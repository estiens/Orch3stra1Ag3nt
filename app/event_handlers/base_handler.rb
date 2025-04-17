# frozen_string_literal: true

# BaseHandler: Base module for event handlers
# Provides common functionality for all event handlers
module BaseHandler
  def self.included(base)
    base.extend(ClassMethods)
  end

  # Class methods mixed in to handler classes
  module ClassMethods
    def handle_event(event)
      new.call(event)
    end
  end

  # Instance method that subclasses should implement
  def call(event)
    raise NotImplementedError, "#{self.class} must implement the call method"
  end

  # Helper to access event data
  def data_from(event)
    event.data
  end

  # Helper to access event metadata
  def metadata_from(event)
    event.metadata
  end

  # Helper to log handler actions
  def log_handler_activity(event, message)
    event_type = event.event_type
    Rails.logger.info("[#{self.class.name}] #{message} for event #{event_type}")
  end
end