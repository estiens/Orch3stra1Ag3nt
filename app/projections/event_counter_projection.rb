# frozen_string_literal: true

# EventCounterProjection: A simple projection that counts events by type
# This serves as an example of how to implement projections with Rails Event Store
class EventCounterProjection
  # Initialize the projection with the event store client
  def initialize(event_store = Rails.configuration.event_store)
    @event_store = event_store
    @counts = Hash.new(0)
  end

  # Build the projection by reading all events
  # This can be called to rebuild the projection from scratch
  def rebuild
    @counts = Hash.new(0)

    # Read all events from the global stream
    @event_store.read.each do |event|
      count_event(event)
    end

    @counts
  end

  # Count a single event
  # This is used for both rebuilding and handling new events
  def count_event(event)
    @counts[event.event_type] += 1
  end

  # Get the current counts
  def counts
    @counts
  end

  # Get the count for a specific event type
  def count_for(event_type)
    @counts[event_type]
  end

  # Subscribe to new events to keep the projection up to date
  def subscribe
    @subscription = @event_store.subscribe(
      ->(event) { count_event(event) },
      to: [ RailsEventStore::ALL_EVENTS ]
    )
  end

  # Unsubscribe to stop updating the projection
  def unsubscribe
    @event_store.unsubscribe(@subscription) if @subscription
    @subscription = nil
  end

  # Create a handler that can be registered with the event store
  def self.create_handler
    projection = new
    projection.rebuild
    projection.subscribe
    projection
  end
end
