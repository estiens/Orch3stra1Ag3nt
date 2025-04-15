# Provides pub/sub functionality for the agent system
# Acts as a central event dispatcher for the application
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
    
    # Initialize the event schema registry
    EventSchemaRegistry.register_standard_schemas
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
    # This method can be used to register default handlers for standard events
    # For example, logging handlers, monitoring handlers, etc.
    Rails.logger.info("Registering standard event handlers")
    
    # Example: Register a logging handler for all events
    if defined?(EventLoggingHandler)
      register_handler("*", EventLoggingHandler, 
                      description: "Logs all events to the database", 
                      priority: 100)
    end
  end

  # Publish an event to all registered handlers
  # @param event [Event] the event to publish
  # @param async [Boolean] whether to process the event asynchronously
  def publish(event, async: true)
    event_type = event.is_a?(Event) ? event.event_type : event[:event_type]

    # Ensure we have an actual event object
    event = Event.create!(event) unless event.is_a?(Event)

    # Log event publishing
    Rails.logger.info("Publishing event: #{event_type} [#{event.id}]")

    handlers = handlers_for(event_type)

    if handlers.empty?
      Rails.logger.info("No handlers registered for event: #{event_type}")
      return
    end

    if async
      # Process asynchronously via a job
      EventDispatchJob.perform_later(event.id)
    else
      # Process synchronously
      dispatch_event(event)
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
          if handler_class.is_a?(Class)
            handler = handler_class.new
            handler.handle_event(event)
          else
            # For test doubles or instances
            handler_class.handle_event(event)
          end
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
