# frozen_string_literal: true

# Initialize the event system
Rails.application.config.after_initialize do
  # Register standard event schemas
  EventSchemaRegistry.register_standard_schemas
  
  # Register standard event handlers
  EventBus.register_standard_handlers
  
  Rails.logger.info("Event system initialized with #{EventSchemaRegistry.registered_schemas.size} schemas")
end
