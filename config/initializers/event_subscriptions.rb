# config/initializers/event_subscriptions.rb

Rails.application.config.after_initialize do
  # Subscribe listeners to the EventBus
  Rails.logger.info "Registering EventBus handlers..."

  listener = ToolExecutionLogger.new

  # Register the listener instance for specific events
  EventBus.register_handler("tool_execution_started", listener)
  EventBus.register_handler("tool_execution_finished", listener)
  EventBus.register_handler("tool_execution_error", listener)

  # Add other subscriptions here if needed
  # Example:
  # EventBus.register_handler('some_other_event', SomeOtherHandler.new)

  Rails.logger.info "EventBus handlers registered."
end
