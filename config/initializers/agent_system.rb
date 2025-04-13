# Initialize the agent system: event bus, tool registry, and error handling

Rails.application.config.after_initialize do
  # Ensure EventBus singleton is initialized
  Rails.logger.info("Initializing agent event system...")

  # Auto-register all tool classes that inherit from Regent::Tool
  Rails.logger.info("Registering agent tools...")

  # Dynamically load tool classes
  Dir[Rails.root.join("app/tools/**/*.rb")].each do |file|
    require_dependency file
  end

  # Configure agent priorities and recurring jobs
  Rails.logger.info("Configuring agent recurring jobs...")

  # Set up system health check with OrchestratorAgent
  if defined?(OrchestratorAgent) && Rails.env.production?
    OrchestratorAgent.configure_recurring_checks("every 30 minutes")
    Rails.logger.info("Configured OrchestratorAgent health check (every 30 minutes)")
  end

  # Set up error reporters
  if Rails.env.production?
    Rails.logger.info("Registering error reporters...")

    # Example: Register Sentry reporter if available
    if defined?(Sentry)
      ErrorHandler.register_reporter(
        Class.new do
          def report(error, context = {})
            Sentry.capture_exception(error, extra: context)
          end
        end.new
      )
      Rails.logger.info("Registered Sentry error reporter")
    end
  end

  # Set up event subscriptions for system agents
  Rails.logger.info("Setting up event subscriptions...")

  # Subscribe OrchestratorAgent to system events if defined
  if defined?(OrchestratorAgent)
    # These are defined in the OrchestratorAgent class
    # but we explicitly log them here for clarity
    Rails.logger.info("OrchestratorAgent subscribed to: task_created, task_stuck, system_resources_critical")
  end

  # Subscribe CoordinatorAgent to task events if defined
  if defined?(CoordinatorAgent)
    # These are defined in the CoordinatorAgent class
    # but we explicitly log them here for clarity
    Rails.logger.info("CoordinatorAgent subscribed to: subtask_completed, subtask_failed, task_waiting_on_human")
  end

  Rails.logger.info("Agent system initialization complete")
end
