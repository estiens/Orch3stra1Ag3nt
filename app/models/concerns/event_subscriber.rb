# Adds event subscription capabilities to a class
# To be included in agents and other event-aware components
module EventSubscriber
  extend ActiveSupport::Concern

  included do
    # Class-level subscriptions
    class_attribute :subscriptions, default: {}

    # Subscribe to an event with a callback
    def self.subscribe_to(event_name, method_name = nil, &block)
      # Use either a method name or a block as the callback
      callback = block_given? ? block : method_name

      # Validate we have a proper callback
      unless callback.is_a?(Symbol) || callback.is_a?(Proc)
        raise ArgumentError, "Must provide either a method name or a block"
      end

      # Store the subscription
      self.subscriptions[event_name.to_s] = callback

      # Register with EventBus
      EventBus.register_handler(event_name.to_s, self)
    end

    # Return the event subscriptions for testing
    def self.event_subscriptions
      self.subscriptions.map do |event_type, method_name|
        { event_type: event_type, method_name: method_name }
      end
    end

    # Class-level method to process an event directly
    # This allows for both class-level and instance-level handling
    def self.process(event)
      # Get the callback for this event type
      callback = self.subscriptions[event.event_type]

      return unless callback

      if callback.is_a?(Symbol)
        # If the callback is a symbol, call the method on the class
        self.send(callback, event)
      elsif callback.is_a?(Proc)
        # If the callback is a proc, execute it in the class context
        self.class_exec(event, &callback)
      end
    end
  end

  # Instance method to process an event
  def handle_event(event)
    event_name = event.event_type
    callback = self.class.subscriptions[event_name]

    return unless callback

    if callback.is_a?(Symbol)
      # Call the method on this instance
      send(callback, event)
    elsif callback.is_a?(Proc)
      # Execute the block in the context of this instance
      instance_exec(event, &callback)
    end
  end
end
