# frozen_string_literal: true

# Initialize the event system core components
# This initializer runs before event_registry.rb to set up the core system
Rails.application.config.after_initialize do
  # Only run in server/console environments, not during asset precompilation
  if defined?(Rails::Server) || Rails.const_defined?('Console')
    Rails.logger.info("Event system core initialized")
    
    # Register system-level handlers that aren't specific to business logic
    # These are handlers that should always be registered regardless of application state
    EventBus.register_standard_handlers
    
    # Clear any existing handlers from test runs if in development mode
    # This prevents duplicate handlers when reloading in development
    if Rails.env.development?
      Rails.logger.debug("Development mode: Ensuring clean event handler registry")
      # We don't clear completely to preserve system handlers, but we could add a method
      # to clear only non-system handlers if needed
    end
  end
end
