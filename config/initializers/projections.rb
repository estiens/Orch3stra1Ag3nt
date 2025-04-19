# frozen_string_literal: true

# Initialize projections after the application is fully loaded
Rails.application.config.after_initialize do
  # Only run in server/console environments, not during asset precompilation
  if defined?(Rails::Server) || Rails.const_defined?("Console")
    unless Rails.env.test? # Skip in test environment to allow for proper stubbing
      # Wait for Rails Event Store to be initialized
      if defined?(Rails.configuration.event_store) && !Rails.configuration.event_store.nil?
        Rails.logger.info("Initializing event projections...")

        # Initialize all projections
        ProjectionManager.initialize_projections

        Rails.logger.info("Event projections initialized")
      else
        Rails.logger.warn("Rails Event Store not initialized, skipping projection initialization")
      end
    end
  end
end
