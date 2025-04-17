# frozen_string_literal: true

# EventBus: Backward compatibility adapter for the legacy event system
# Provides a bridge between the old event system and Rails Event Store
class EventBus
  # Singleton pattern for the EventBus
  include Singleton

  # Class methods - delegates to instance
  class << self
    delegate :publish, :register_handler, :handlers_for, :clear_handlers!,
             :register_standard_handlers, :handler_registry, to: :instance

    # Alias for register_handler to maintain backward compatibility with tests
    def subscribe(event_type, handler, method_name = :process)
      instance.register_handler(event_type, handler)
    end
  end

  def initialize
    @handlers = Hash.new { |hash, key| hash[key] = [] }
    @handler_metadata = {}
    @mutex = Mutex.new
  end

  # Register a handler for a specific event type
  # @param event_type [String] the event type to subscribe to
  # @param handler [Class] the class that will handle this event
  # @param description [String] optional description of what this handler does
  # @param priority [Integer] optional priority (higher numbers run first)
  def register_handler(event_type, handler, description: nil, priority: 10)
    @mutex.synchronize do
      # Only add the handler if it's not already registered for this event type
      unless @handlers[event_type.to_s].include?(handler)
        @handlers[event_type.to_s] << handler

        # Store metadata about this handler
        @handler_metadata["#{event_type}:#{handler}"] = {
          description: description || "No description provided",
          priority: priority,
          registered_at: Time.current
        }
      end
    end
  end

  # Get all handlers registered for an event type
  # @param event_type [String] the event type to get handlers for
  # @return [Array] array of handler classes
  def handlers_for(event_type)
    @mutex.synchronize do
      # Sort handlers by priority (higher numbers first)
      @handlers[event_type.to_s].sort_by do |handler|
        -(@handler_metadata["#{event_type}:#{handler}"][:priority] || 0)
      end
    end
  end

  # Get the full handler registry with metadata
  # @return [Hash] the handler registry
  def handler_registry
    @mutex.synchronize do
      result = {}

      @handlers.each do |event_type, handlers|
        result[event_type] = handlers.map do |handler|
          {
            handler: handler,
            metadata: @handler_metadata["#{event_type}:#{handler}"]
          }
        end
      end

      result
    end
  end

  # Clear all event handlers (useful for testing)
  def clear_handlers!
    @mutex.synchronize do
      @handlers.clear
      @handler_metadata.clear
    end
  end

  # Register standard handlers for common events
  def register_standard_handlers
    # This method registers system-level handlers that should always be present
    # These are handlers for core functionality, not business logic
    Rails.logger.info("Registering standard event handlers")

    # Register a logging handler for all events if available
    if defined?(EventLoggingHandler)
      register_handler("*", EventLoggingHandler,
                     description: "Logs all events to the database",
                     priority: 100)
    end

    # Register a metrics/monitoring handler if available
    if defined?(EventMetricsHandler)
      register_handler("*", EventMetricsHandler,
                     description: "Collects metrics for all events",
                     priority: 90)
    end

    # Register a debugging handler in development environment
    if Rails.env.development? && defined?(EventDebugHandler)
      register_handler("*", EventDebugHandler,
                     description: "Provides debug information for events in development",
                     priority: 110)
    end
  end

  # Publish an event to all registered handlers
  # @param event [Event] the event to publish
  # @param async [Boolean] whether to process the event asynchronously
  def publish(event, async: true)
    # Figure out what kind of event we have
    if event.is_a?(Event)
      # We have a legacy Event record
      event_type = event.event_type
      data = event.data
      metadata = {
        agent_activity_id: event.agent_activity_id,
        task_id: event.task_id,
        project_id: event.project_id
      }
    elsif event.is_a?(Hash)
      # We have a hash with event data
      event_type = event[:event_type]
      data = event[:data] || {}
      metadata = {
        agent_activity_id: event[:agent_activity_id],
        task_id: event[:task_id],
        project_id: event[:project_id]
      }

      # Create an Event record for legacy handlers
      event = Event.create!(
        event_type: event_type,
        data: data,
        agent_activity_id: metadata[:agent_activity_id],
        task_id: metadata[:task_id],
        project_id: metadata[:project_id]
      )
    else
      # We have a Rails Event Store event
      event_type = event.event_type
      data = event.data
      metadata = event.metadata

      # Create an Event record for legacy handlers
      event = Event.create!(
        event_type: event_type,
        data: data,
        agent_activity_id: metadata[:agent_activity_id],
        task_id: metadata[:task_id],
        project_id: metadata[:project_id]
      )
    end

    # Log event publishing
    Rails.logger.info("Legacy EventBus publishing event: #{event_type} [#{event.id}]")

    if async
      # Process asynchronously via a job
      EventDispatchJob.perform_later(event.id)
    else
      # Process synchronously
      dispatch_event(event)
    end

    # Also publish through the new EventService if it's not already coming from there
    # This ensures both systems receive the event
    # BUT only if we're not already receiving an RES event to avoid loops
    unless event.is_a?(RailsEventStore::Event)
      EventService.publish(event_type, data, metadata)
    end

    event
  end

  # Dispatches an event to all registered handlers
  # @param event [Event] the event to dispatch
  def dispatch_event(event)
    event_type = event.event_type
    handlers = handlers_for(event_type)

    Rails.logger.debug("Dispatching event: #{event_type} [#{event.id}] to #{handlers.size} handlers")

    handlers.each do |handler_class|
      begin
        # Check if BaseAgent is defined before checking inheritance
        if defined?(BaseAgent) && handler_class.is_a?(Class) && handler_class < BaseAgent
          # Dispatch to an agent job
          handler_options = {
            purpose: "Process #{event_type} event",
            event_id: event.id
          }
          handler_class.enqueue("Process event: #{event_type}", handler_options)
        elsif handler_class.respond_to?(:process)
          # Use the process class method for classes and test doubles
          handler_class.process(event)
        elsif handler_class.respond_to?(:handle_event)
          # Use the handle_event method if available (for instance methods)
          handler_class.handle_event(event)
        elsif handler_class.is_a?(Class) && handler_class.instance_methods.include?(:handle_event)
          # For classes with instance method handle_event
          handler = handler_class.new
          handler.handle_event(event)
        else
          Rails.logger.warn("Handler #{handler_class} does not respond to process or handle_event")
        end
      rescue => e
        Rails.logger.error("Error dispatching event #{event_type} to #{handler_class}: #{e.message}")
        # Mark event as processed with error
        event.record_processing_attempt!(e) if event.respond_to?(:record_processing_attempt!)
      end
    end
  end
end