require 'rails_helper'

RSpec.describe EventBus do
  # Create a test subscriber for our tests
  class TestEventBusSubscriber
    include EventSubscriber

    subscribe_to 'test_bus_event'

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
    # Temporarily clear other subscribers to isolate our tests
    @original_subscribers = EventBus.instance_variable_get(:@subscribers)
    EventBus.instance_variable_set(:@subscribers, {})
    # Register our test subscriber
    EventBus.register('test_bus_event', TestEventBusSubscriber)
  end

  after(:each) do
    # Restore the original subscribers
    EventBus.instance_variable_set(:@subscribers, @original_subscribers)
  end

  describe '.publish' do
    it 'delivers events to the appropriate subscribers' do
      event = Event.new(event_type: 'test_bus_event', data: { message: 'Hello' })

      EventBus.publish(event)

      expect(TestEventBusSubscriber.processed_events).to include(event)
    end

    it 'does not deliver events to unsubscribed handlers' do
      event = Event.new(event_type: 'unsubscribed_event', data: { message: 'Hello' })

      EventBus.publish(event)

      expect(TestEventBusSubscriber.processed_events).to be_empty
    end

    it 'handles multiple subscribers for the same event type' do
      class AnotherTestSubscriber
        include EventSubscriber

        subscribe_to 'test_bus_event'

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
      EventBus.register('test_bus_event', AnotherTestSubscriber)

      event = Event.new(event_type: 'test_bus_event', data: { message: 'Hello' })
      EventBus.publish(event)

      expect(TestEventBusSubscriber.processed_events).to include(event)
      expect(AnotherTestSubscriber.processed?).to be true
    end
  end

  describe '.register' do
    it 'registers a subscriber for an event type' do
      EventBus.register('new_event_type', TestEventBusSubscriber)

      event = Event.new(event_type: 'new_event_type', data: { message: 'New Event' })
      EventBus.publish(event)

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

      EventBus.register('shared_event', SubscriberOne)
      EventBus.register('shared_event', SubscriberTwo)

      subscribers = EventBus.instance_variable_get(:@subscribers)['shared_event']
      expect(subscribers).to include(SubscriberOne)
      expect(subscribers).to include(SubscriberTwo)
    end
  end

  describe '.subscribers_for' do
    it 'returns subscribers for a given event type' do
      subscribers = EventBus.subscribers_for('test_bus_event')
      expect(subscribers).to include(TestEventBusSubscriber)
    end

    it 'returns an empty array for event types with no subscribers' do
      subscribers = EventBus.subscribers_for('nonexistent_event')
      expect(subscribers).to be_empty
    end
  end
end
