require 'rails_helper'

RSpec.describe EventBus do
  # Create a test subscriber for our tests
  class TestEventBusSubscriber
    include EventSubscriber

    subscribe_to 'test_bus_event', :process

    def self.process(event)
      @processed_events ||= []
      @processed_events << event
    end

    def self.processed_events
      @processed_events ||= []
    end

    def self.reset!
      @processed_events = []
    end
  end

  before(:each) do
    TestEventBusSubscriber.reset!
    # Temporarily clear other handlers to isolate our tests
    @original_handlers = EventBus.instance.instance_variable_get(:@handlers)
    EventBus.instance.instance_variable_set(:@handlers, Hash.new { |hash, key| hash[key] = [] })
    # Register our test subscriber
    EventBus.register_handler('test_bus_event', TestEventBusSubscriber)
  end

  after(:each) do
    # Restore the original handlers
    EventBus.instance.instance_variable_set(:@handlers, @original_handlers)
  end

  describe '.publish' do
    it 'delivers events to the appropriate subscribers' do
      event = Event.new(event_type: 'test_bus_event', data: { message: 'Hello' })

      EventBus.publish(event, async: false)

      expect(TestEventBusSubscriber.processed_events).to include(event)
    end

    it 'does not deliver events to unsubscribed handlers' do
      event = Event.new(event_type: 'unsubscribed_event', data: { message: 'Hello' })

      EventBus.publish(event, async: false)

      expect(TestEventBusSubscriber.processed_events).to be_empty
    end

    it 'handles multiple subscribers for the same event type' do
      class AnotherTestSubscriber
        include EventSubscriber

        subscribe_to 'test_bus_event', :process

        def self.process(event)
          @processed = true
        end

        def self.processed?
          @processed || false
        end

        def self.reset!
          @processed = false
        end
      end

      AnotherTestSubscriber.reset!
      EventBus.register_handler('test_bus_event', AnotherTestSubscriber)

      event = Event.new(event_type: 'test_bus_event', data: { message: 'Hello' })
      EventBus.publish(event, async: false)

      expect(TestEventBusSubscriber.processed_events).to include(event)
      expect(AnotherTestSubscriber.processed?).to be true
    end
  end

  describe '.register_handler' do
    it 'registers a subscriber for an event type' do
      EventBus.register_handler('new_event_type', TestEventBusSubscriber)

      event = Event.new(event_type: 'new_event_type', data: { message: 'New Event' })
      EventBus.publish(event, async: false)

      expect(TestEventBusSubscriber.processed_events).to include(event)
    end

    it 'allows multiple subscribers for the same event type' do
      class SubscriberOne
        include EventSubscriber
        def self.process(event); end
      end

      class SubscriberTwo
        include EventSubscriber
        def self.process(event); end
      end

      EventBus.register_handler('shared_event', SubscriberOne)
      EventBus.register_handler('shared_event', SubscriberTwo)

      handlers = EventBus.instance.instance_variable_get(:@handlers)['shared_event']
      expect(handlers).to include(SubscriberOne)
      expect(handlers).to include(SubscriberTwo)
    end
  end

  describe '.handlers_for' do
    it 'returns subscribers for a given event type' do
      handlers = EventBus.handlers_for('test_bus_event')
      expect(handlers).to include(TestEventBusSubscriber)
    end

    it 'returns an empty array for event types with no subscribers' do
      handlers = EventBus.handlers_for('nonexistent_event')
      expect(handlers).to be_empty
    end
  end
end
