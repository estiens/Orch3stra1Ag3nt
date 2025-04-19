# Event Projections

This directory contains event projections for the application. Projections are read models built from events that provide efficient querying capabilities.

## What are Projections?

Projections transform event streams into queryable data structures. They:

1. Subscribe to events
2. Update their internal state based on those events
3. Provide query methods to access the data

Projections are particularly useful for:
- Building dashboards and reports
- Providing efficient read models for specific queries
- Extracting statistics and metrics from event data

## Available Projections

### EventCounterProjection

A simple projection that counts events by type. It provides:

- `counts`: Get all event type counts
- `count_for(event_type)`: Get the count for a specific event type

## Using Projections

Projections are managed by the `ProjectionManager` service. To use a projection:

```ruby
# Get the event counter projection
counter = ProjectionManager.get(:event_counter)

# Get counts for all event types
all_counts = counter.counts
# => {"tool_execution.started" => 42, "agent.completed" => 17, ...}

# Get count for a specific event type
tool_start_count = counter.count_for("tool_execution.started")
# => 42
```

## Creating New Projections

To create a new projection:

1. Create a new class in the `app/projections` directory
2. Implement the following methods:
   - `initialize(event_store)`: Set up the projection
   - `rebuild`: Rebuild the projection from scratch
   - `subscribe`: Subscribe to events
   - `unsubscribe`: Unsubscribe from events
   - `self.create_handler`: Create and configure a handler instance
3. Register the projection in `ProjectionManager.initialize_projections`

Example:

```ruby
class MyProjection
  def initialize(event_store = Rails.configuration.event_store)
    @event_store = event_store
    @data = {}
  end

  def rebuild
    @data = {}
    @event_store.read.each do |event|
      process_event(event)
    end
    @data
  end

  def process_event(event)
    # Update @data based on the event
  end

  def subscribe
    @subscription = @event_store.subscribe(
      ->(event) { process_event(event) },
      to: [MyEvent1, MyEvent2]
    )
  end

  def unsubscribe
    @event_store.unsubscribe(@subscription) if @subscription
    @subscription = nil
  end

  def self.create_handler
    projection = new
    projection.rebuild
    projection.subscribe
    projection
  end
end

# In ProjectionManager.initialize_projections:
register(:my_projection, MyProjection)
```

## Rebuilding Projections

Projections can be rebuilt if they get out of sync or if the projection logic changes:

```ruby
# Rebuild a specific projection
ProjectionManager.rebuild(:event_counter)

# Rebuild all projections
ProjectionManager.rebuild_all
```

## Performance Considerations

- Projections should be efficient, especially in their `process_event` method
- Consider using batch processing for rebuilding large projections
- For very large event streams, consider using background jobs for rebuilding
- Use appropriate data structures for your query patterns