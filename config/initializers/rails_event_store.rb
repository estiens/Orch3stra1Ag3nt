# frozen_string_literal: true

# Configure Rails Event Store for the application
Rails.application.config.after_initialize do
  unless Rails.env.test? # Skip in test environment to allow for proper stubbing

  # Create the event store client
  Rails.configuration.event_store = RailsEventStore::Client.new(
    repository: RailsEventStoreActiveRecord::EventRepository.new,
    serializer: RubyEventStore::Serializers::JSON.new
  )

  # Configuration flag to determine if we should also create legacy Event records
  # This is useful during the transition period
  Rails.configuration.create_event_records = true

  # Add basic logging middleware
  Rails.configuration.event_store.subscribe(
    ->(event) { Rails.logger.info("RES Event published: #{event.event_type} #{event.metadata[:correlation_id]}") },
    to: [RailsEventStore::ALL_EVENTS]
  )
  end # End of unless Rails.env.test?
end