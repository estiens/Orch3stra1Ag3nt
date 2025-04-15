# frozen_string_literal: true

# Initialize the event system core components
Rails.application.config.after_initialize do
  # Only run in server/console environments, not during asset precompilation
  if defined?(Rails::Server) || Rails.const_defined?('Console')
    Rails.logger.info("Event system core initialized")
    
    # Register any system-level handlers that aren't specific to business logic
    # These are handlers that should always be registered regardless of application state
    EventBus.register_standard_handlers
  end
end
