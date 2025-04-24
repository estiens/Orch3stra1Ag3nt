require "rails_event_store"
require "aggregate_root"
require "arkency/command_bus"

Rails.configuration.to_prepare do
  Rails.configuration.event_store = RailsEventStore::JSONClient.new

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
  # Subscribe event handlers below
  Rails.configuration.event_store.tap do |store|
    # store.subscribe(InvoiceReadModel.new, to: [InvoicePrinted])
    # store.subscribe(lambda { |event| SendOrderConfirmation.new.call(event) }, to: [OrderSubmitted])
    # store.subscribe_to_all_events(lambda { |event| Rails.logger.info(event.event_type) })

    store.subscribe_to_all_events(RailsEventStore::LinkByEventType.new)
    store.subscribe_to_all_events(RailsEventStore::LinkByCorrelationId.new)
    store.subscribe_to_all_events(RailsEventStore::LinkByCausationId.new)
  end

  # Register command handlers below
  # Rails.configuration.command_bus.tap do |bus|
  #   bus.register(PrintInvoice, Invoicing::OnPrint.new)
  #   bus.register(SubmitOrder, ->(cmd) { Ordering::OnSubmitOrder.new.call(cmd) })
  # end
end
# frozen_string_literal: true

# Event Subscriptions Initializer
# Registers all event handlers with the RailsEventStore
Rails.application.config.to_prepare do
  # Only run in server/console environments, not during asset precompilation
  if defined?(Rails::Server) || Rails.const_defined?("Console")
    Rails.logger.info("Initializing Rails Event Store subscriptions...")

      # Subscribe handlers to events


      # System events
      if defined?(SystemEventHandler)
        store.subscribe(
          SystemEventHandler,
          to: [
            SystemEvents::SystemStartupEvent,
            SystemEvents::SystemShutdownEvent,
            SystemEvents::SystemErrorEvent,
            SystemEvents::SystemConfigChangedEvent
          ]
        )
        Rails.logger.info("Registered SystemEventHandler with Rails Event Store")
      end

      # Agent events
      if defined?(AgentEventHandler)
        store.subscribe(
          AgentEventHandler,
          to: [
            AgentEvents::AgentStartedEvent,
            AgentEvents::AgentCompletedEvent,
            AgentEvents::AgentPausedEvent,
            AgentEvents::AgentResumedEvent,
            AgentEvents::AgentRequestedHumanEvent
          ]
        )
        Rails.logger.info("Registered AgentEventHandler with Rails Event Store")
      end

      # Dashboard event handler for real-time updates
      if defined?(DashboardEventHandler)
        # Register with RailsEventStore for all event types
        dashboard_handler = DashboardEventHandler.new

        # Dashboard will listen to all events for broadcasting updates
        store.subscribe(
          dashboard_handler,
          to: [
            # Task events (using new classes)
            TaskEvents::TaskActivatedEvent,
            TaskEvents::TaskPausedEvent,
            TaskEvents::TaskResumedEvent,
            TaskEvents::TaskCompletedEvent,
            TaskEvents::TaskFailedEvent,
            # Project events
            "project.activated", "project.paused", "project.resumed", "project.completed",
            # Human input events
            "human_input.requested", "human_input.provided", "human_input.ignored",
            # Agent activity events
            "agent_activity.created", "agent_activity.completed", "agent_activity.failed",
            # LLM call events
            "llm_call.completed"
          ]
        )

        Rails.logger.info("Registered DashboardEventHandler with Rails Event Store")
      end

    # Add other handler registrations here
    # Example:
    # store.subscribe(SomeOtherHandler, to: [SomeEvent, AnotherEvent])
  end

    Rails.logger.info("Rails Event Store subscriptions initialized")
  end
end
