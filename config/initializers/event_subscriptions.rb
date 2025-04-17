# frozen_string_literal: true

# Event Subscriptions Initializer
# Registers all event handlers with the RailsEventStore
Rails.application.config.to_prepare do
  # Only run in server/console environments, not during asset precompilation
  if defined?(Rails::Server) || Rails.const_defined?("Console")
    Rails.logger.info("Initializing Rails Event Store subscriptions...")

    # Subscribe handlers to events
    Rails.configuration.event_store.tap do |store|
      # Tool execution events
      if defined?(ToolExecutionHandler)
        store.subscribe(
          ToolExecutionHandler,
          to: [
            ToolEvents::ToolExecutionStartedEvent,
            ToolEvents::ToolExecutionFinishedEvent,
            ToolEvents::ToolExecutionErrorEvent
          ]
        )
        Rails.logger.info("Registered ToolExecutionHandler with Rails Event Store")
      end

      # Dashboard event handler for real-time updates
      if defined?(DashboardEventHandler)
        # Register through our adapter for now
        # We'll transition to direct RES subscriptions later
        # This uses the legacy events for now
        listener = DashboardEventHandler.new

        # Legacy registrations through EventBus
        EventBus.register_handler("task_activated", listener)
        EventBus.register_handler("task_paused", listener)
        EventBus.register_handler("task_resumed", listener)
        EventBus.register_handler("task_completed", listener)
        EventBus.register_handler("task_failed", listener)
        EventBus.register_handler("project_activated", listener)
        EventBus.register_handler("project_paused", listener)
        EventBus.register_handler("project_resumed", listener)
        EventBus.register_handler("project_completed", listener)
        EventBus.register_handler("human_input_requested", listener)
        EventBus.register_handler("human_input_provided", listener)
        EventBus.register_handler("human_input_ignored", listener)
        EventBus.register_handler("agent_activity_created", listener)
        EventBus.register_handler("agent_activity_completed", listener)
        EventBus.register_handler("agent_activity_failed", listener)
        EventBus.register_handler("llm_call_completed", listener)

        Rails.logger.info("Registered DashboardEventHandler with Legacy EventBus")
      end

      # Add other handler registrations here
      # Example:
      # store.subscribe(SomeOtherHandler, to: [SomeEvent, AnotherEvent])
    end

    Rails.logger.info("Rails Event Store subscriptions initialized")
  end
end