# Provides pub/sub functionality for the agent system
# Acts as a central event dispatcher for the application
class EventBus
  # Singleton pattern for the EventBus
  include Singleton

  # Class methods - delegates to instance
  class << self
    delegate :publish, :register_handler, :handlers_for, :clear_handlers!, to: :instance
  end

  def initialize
    @handlers = Hash.new { |hash, key| hash[key] = [] }
    @mutex = Mutex.new
  end

  # Register a handler for a specific event type
  # @param event_type [String] the event type to subscribe to
  # @param handler [Class] the class that will handle this event
  def register_handler(event_type, handler)
    @mutex.synchronize do
      @handlers[event_type.to_s] << handler unless @handlers[event_type.to_s].include?(handler)
    end
  end

  # Get all handlers registered for an event type
  # @param event_type [String] the event type to get handlers for
  # @return [Array] array of handler classes
  def handlers_for(event_type)
    @mutex.synchronize do
      @handlers[event_type.to_s].dup
    end
  end

  # Clear all event handlers (useful for testing)
  def clear_handlers!
    @mutex.synchronize do
      @handlers.clear
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
        # If the handler is an agent class
        if handler_class < BaseAgent
          # Dispatch to an agent job
          handler_options = {
            purpose: "Process #{event_type} event",
            event_id: event.id
          }
          handler_class.enqueue("Process event: #{event_type}", handler_options)
        else
          # Create an instance and handle directly
          handler = handler_class.new
          handler.handle_event(event) if handler.respond_to?(:handle_event)
        end
      rescue => e
        Rails.logger.error("Error dispatching event #{event_type} to #{handler_class}: #{e.message}")
        # Avoid failing all handlers if one fails
      end
    end
  end
end
