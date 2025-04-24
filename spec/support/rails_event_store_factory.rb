# frozen_string_literal: true

# Helper for creating RailsEventStore events in specs
module RailsEventStoreFactory
  def build_res_event(event_class, data: {}, metadata: {})
    # Convert class string to actual class if needed
    klass = event_class.is_a?(String) ? event_class.constantize : event_class

    # Create the event
    klass.new(data: data, metadata: metadata)
  end

  def publish_res_event(event_class, data: {}, metadata: {})
    event = build_res_event(event_class, data: data, metadata: metadata)
    Rails.configuration.event_store.publish(event)
    event
  end
end

RSpec.configure do |config|
  config.include RailsEventStoreFactory
end
