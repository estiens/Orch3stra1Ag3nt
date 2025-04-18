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

      # Subscribe through Rails Event Store directly
      # Convert event_name to dot notation if needed
      event_type = event_name.to_s.include?('.') ? event_name.to_s : EventMigrationExample.map_legacy_to_new_event_type(event_name.to_s)
      
      # Use Rails Event Store's subscribe method instead of the legacy EventBus
      # Skip actual subscription in test environment - we'll handle this separately in tests
      unless Rails.env.test?
        if defined?(Rails.configuration.event_store) && Rails.configuration.event_store
          Rails.configuration.event_store.subscribe(self, to: [event_type])
        end
      end
    end

    # Return the event subscriptions for testing
    def self.event_subscriptions
      self.subscriptions.map do |event_type, method_name|
        { event_type: event_type, method_name: method_name }
      end
    end

    # Method to handle events from Rails Event Store
    # Implements the call interface required by RailsEventStore
    def self.call(event)
      # Get the callback for this event type (handle both legacy and new format)
      event_type = event.event_type.to_s
      legacy_event_type = event_type.gsub('.', '_')
      
      callback = self.subscriptions[event_type] || self.subscriptions[legacy_event_type]
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

  # Instance method to handle events
  # Implements call() interface for RailsEventStore handlers
  def call(event)
    event_type = event.event_type.to_s
    legacy_event_type = event_type.gsub('.', '_')
    
    callback = self.class.subscriptions[event_type] || self.class.subscriptions[legacy_event_type]
    return unless callback

    if callback.is_a?(Symbol)
      # Call the method on this instance
      send(callback, event)
    elsif callback.is_a?(Proc)
      # Execute the block in the context of this instance
      instance_exec(event, &callback)
    end
  end
  
  # Legacy method for backward compatibility
  def handle_event(event)
    call(event)
  end
end
