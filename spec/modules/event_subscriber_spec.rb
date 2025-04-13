require 'rails_helper'

# Define test classes outside the tests to avoid constant redefinition warnings
module EventSubscriberTest
  class TestSubscriber
    include EventSubscriber

    subscribe_to 'test_event', :process

    def self.process(event)
      # Implementation for testing
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

  class MultiEventSubscriber
    include EventSubscriber

    subscribe_to 'event_one', :process
    subscribe_to 'event_two', :process

    def self.process(event)
      # Implementation for testing
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
end

RSpec.describe EventSubscriber do
  let(:agent_activity) { create(:agent_activity) }

  before(:each) do
    # Reset the handlers
    EventBus.instance.clear_handlers!
    # Reset test classes
    EventSubscriberTest::TestSubscriber.reset!
    EventSubscriberTest::MultiEventSubscriber.reset!
    # Register the handlers
    EventBus.register_handler('test_event', EventSubscriberTest::TestSubscriber)
    EventBus.register_handler('event_one', EventSubscriberTest::MultiEventSubscriber)
    EventBus.register_handler('event_two', EventSubscriberTest::MultiEventSubscriber)
  end

  after(:each) do
    # Clean up after tests
    EventBus.instance.clear_handlers!
  end

  describe '.subscribe_to' do
    it 'registers the class with EventBus for specified event types' do
      expect(EventBus.handlers_for('test_event')).to include(EventSubscriberTest::TestSubscriber)
    end

    it 'can register for multiple event types' do
      expect(EventBus.handlers_for('event_one')).to include(EventSubscriberTest::MultiEventSubscriber)
      expect(EventBus.handlers_for('event_two')).to include(EventSubscriberTest::MultiEventSubscriber)
    end

    it 'requires a valid callback to be provided' do
      expect {
        Class.new do
          include EventSubscriber
          subscribe_to 'invalid_event'
          # Missing callback parameter
        end
      }.to raise_error(ArgumentError, "Must provide either a method name or a block")
    end

    it 'allows multiple subscribers to listen to the same event' do
      # Define classes inline with unique names
      first_subscriber = Class.new do
        include EventSubscriber
        subscribe_to 'shared_event', :process
        def self.process(event); end
        def self.name; "FirstSubscriber"; end
      end

      second_subscriber = Class.new do
        include EventSubscriber
        subscribe_to 'shared_event', :process
        def self.process(event); end
        def self.name; "SecondSubscriber"; end
      end

      handlers = EventBus.handlers_for('shared_event')
      expect(handlers).to include(first_subscriber)
      expect(handlers).to include(second_subscriber)
    end
  end

  describe 'processing' do
    let(:event) { Event.create!(event_type: 'test_event', agent_activity: agent_activity, data: { foo: 'bar' }) }

    it 'processes events via the EventBus' do
      expect(EventSubscriberTest::TestSubscriber).to receive(:process).with(event)
      EventBus.publish(event, async: false)
    end

    it 'only receives events it subscribed to' do
      other_event = Event.create!(event_type: 'unsubscribed_event', agent_activity: agent_activity, data: { baz: 'qux' })

      expect(EventSubscriberTest::TestSubscriber).not_to receive(:process)
      EventBus.publish(other_event, async: false)
    end

    it 'actually processes the events through the class method' do
      EventBus.publish(event, async: false)
      expect(EventSubscriberTest::TestSubscriber.processed_events).to include(event)
    end
  end
end
