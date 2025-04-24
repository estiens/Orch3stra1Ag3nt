# Event System

This directory contains the event system for the application. The event system is built on top of Rails Event Store and provides a way to publish and subscribe to events.

## Event Structure

Events in our system follow a consistent structure:

1. **BaseEvent**: The base class for all events, inheriting from `RailsEventStore::Event`.
2. **Namespaced Event Classes**: Events are organized into namespaces based on their domain (e.g., `ToolEvents`, `AgentEvents`, `SystemEvents`).
3. **Schema Validation**: Each event class defines a schema using Dry::Schema to validate event data.
4. **Backward Compatibility**: Events create legacy Event records for backward compatibility.

## Event Types

### Tool Events
- `ToolEvents::ToolExecutionStartedEvent`: When a tool starts execution
- `ToolEvents::ToolExecutionFinishedEvent`: When a tool completes execution
- `ToolEvents::ToolExecutionErrorEvent`: When a tool execution encounters an error

### Agent Events
- `AgentEvents::AgentStartedEvent`: When an agent starts its execution
- `AgentEvents::AgentCompletedEvent`: When an agent completes its execution
- `AgentEvents::AgentPausedEvent`: When an agent is paused
- `AgentEvents::AgentResumedEvent`: When an agent resumes after being paused
- `AgentEvents::AgentRequestedHumanEvent`: When an agent requests human intervention

### System Events
- `SystemEvents::SystemStartupEvent`: When the system starts up
- `SystemEvents::SystemShutdownEvent`: When the system shuts down
- `SystemEvents::SystemErrorEvent`: When a system-level error occurs
- `SystemEvents::SystemConfigChangedEvent`: When system configuration changes

## Publishing Events

To publish an event, use the `EventService`:

```ruby
# Publishing a tool execution started event
EventService.publish(
  "tool_execution.started",
  {
    tool: "search_web",
    args: { query: "Rails Event Store" }
  },
  {
    task_id: task.id,
    agent_activity_id: activity.id
  }
)

# Publishing an agent started event
EventService.publish(
  "agent.started",
  {
    agent_type: "researcher",
    agent_id: "agent-123",
    purpose: "Research Rails Event Store"
  },
  {
    task_id: task.id,
    agent_activity_id: activity.id
  }
)

# Publishing a system error event
EventService.publish(
  "system.error",
  {
    error_type: "DatabaseConnectionError",
    message: "Failed to connect to database",
    component: "DatabaseAdapter",
    severity: "critical"
  }
)
```

## Handling Events

Events are handled by subscribers that are registered in `config/initializers/event_subscriptions.rb`. Each handler is responsible for processing specific event types.

To create a new handler:

1. Create a class that includes `BaseHandler`
2. Implement the `call` method that takes an event as an argument
3. Register the handler in `config/initializers/event_subscriptions.rb`

Example:

```ruby
class MyEventHandler
  include BaseHandler

  def call(event)
    case event.event_type
    when "my_domain.some_event"
      # Handle the event
    end
  end
end

# In config/initializers/event_subscriptions.rb
Rails.configuration.event_store.tap do |store|
  store.subscribe(
    MyEventHandler,
    to: [MyDomainEvents::SomeEvent]
  )
end
```

## Creating New Event Types

To create a new event type:

1. Create a new class in the appropriate namespace
2. Inherit from `BaseEvent`
3. Define a schema using Dry::Schema
4. Implement the `event_type` class method
5. Implement the `valid?` and `validation_errors` methods

Example:

```ruby
module MyDomainEvents
  class SomeEvent < BaseEvent
    SCHEMA = Dry::Schema.Params do
      required(:some_field).filled(:string)
      optional(:other_field).maybe(:integer)
    end

    def self.event_type
      "my_domain.some_event"
    end

    def valid?
      errors = validation_errors
      errors.empty?
    end

    def validation_errors
      SCHEMA.call(data).errors.to_h
    end
  end
end
```

## Event Streams

Events are stored in streams based on their metadata:

- Task streams: `task-{task_id}`
- Agent activity streams: `agent-activity-{agent_activity_id}`
- Project streams: `project-{project_id}`
- Global stream: `all`

This allows for efficient querying of events for specific entities.

## Backward Compatibility

The event system maintains backward compatibility with the legacy Event model. Each event published through the EventService also creates a legacy Event record, which allows existing code to continue working while we transition to the new event system.