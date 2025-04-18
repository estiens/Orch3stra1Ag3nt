require 'rails_helper'

RSpec.describe EventBus do
  let(:agent_activity) { create(:agent_activity) }

  before(:each) do
    # Get a fresh instance for each test
    @bus = EventBus.instance
    @bus.clear_handlers!
  end

  after(:each) do
    # Clean up handlers after each test
    @bus.clear_handlers!
  end

  describe '.subscribe' do
    it 'registers a subscriber for an event type' do
      test_subscriber = Class.new do
        def self.process(event)
          # Test subscriber
        end
      end

      EventBus.subscribe('test_event', test_subscriber)

      handlers = @bus.instance_variable_get(:@handlers)
      expect(handlers['test_event']).to include(test_subscriber)
    end

    it 'allows multiple subscribers for the same event type' do
      test_subscriber1 = Class.new do
        def self.process(event)
          # Test subscriber 1
        end
      end

      test_subscriber2 = Class.new do
        def self.process(event)
          # Test subscriber 2
        end
      end

      EventBus.subscribe('test_event', test_subscriber1)
      EventBus.subscribe('test_event', test_subscriber2)

      handlers = @bus.instance_variable_get(:@handlers)
      expect(handlers['test_event']).to include(test_subscriber1, test_subscriber2)
    end
  end

  describe '.register_handler' do
    it 'registers a handler with metadata' do
      test_handler = Class.new do
        def self.process(event)
          # Test handler
        end
      end

      EventBus.register_handler('test_event', test_handler,
                               description: 'Test handler description',
                               priority: 20)

      handlers = @bus.instance_variable_get(:@handlers)
      expect(handlers['test_event']).to include(test_handler)

      metadata = @bus.instance_variable_get(:@handler_metadata)
      expect(metadata['test_event:' + test_handler.to_s][:description]).to eq('Test handler description')
      expect(metadata['test_event:' + test_handler.to_s][:priority]).to eq(20)
    end
  end

  describe '.handlers_for' do
    it 'returns handlers sorted by priority' do
      high_priority = Class.new do
        def self.process(event); end
      end

      low_priority = Class.new do
        def self.process(event); end
      end

      EventBus.register_handler('test_event', low_priority, priority: 10)
      EventBus.register_handler('test_event', high_priority, priority: 30)

      handlers = EventBus.handlers_for('test_event')
      expect(handlers.first).to eq(high_priority)
      expect(handlers.last).to eq(low_priority)
    end
  end

  describe '.handler_registry' do
    it 'returns the full handler registry with metadata' do
      test_handler = Class.new do
        def self.process(event); end
      end

      EventBus.register_handler('test_event', test_handler,
                               description: 'Test description',
                               priority: 15)

      registry = EventBus.handler_registry
      expect(registry['test_event']).to be_an(Array)
      expect(registry['test_event'].first[:handler]).to eq(test_handler)
      expect(registry['test_event'].first[:metadata][:description]).to eq('Test description')
      expect(registry['test_event'].first[:metadata][:priority]).to eq(15)
    end
  end

  describe '.publish' do
    let(:event) { Event.create!(event_type: 'test_event', agent_activity: agent_activity, data: { foo: 'bar' }) }

    it 'notifies all subscribers for the event type' do
      test_subscriber1 = double('Subscriber1_publish_1')
      test_subscriber2 = double('Subscriber2_publish_1')

      allow(test_subscriber1).to receive(:respond_to?).with(:process).and_return(true)
      allow(test_subscriber2).to receive(:respond_to?).with(:process).and_return(true)

      expect(test_subscriber1).to receive(:process).with(event)
      expect(test_subscriber2).to receive(:process).with(event)

      EventBus.subscribe('test_event', test_subscriber1)
      EventBus.subscribe('test_event', test_subscriber2)

      EventBus.publish(event, async: false)
    end

    it 'does not notify subscribers for other event types' do
      test_subscriber = double('Subscriber_publish_2')

      allow(test_subscriber).to receive(:respond_to?).with(:process).and_return(true)
      expect(test_subscriber).not_to receive(:process)

      EventBus.subscribe('other_event', test_subscriber)

      EventBus.publish(event, async: false)
    end

    it 'handles errors from subscribers without affecting other subscribers' do
      error_subscriber = double('ErrorSubscriber_publish_3')
      working_subscriber = double('WorkingSubscriber_publish_3')

      allow(error_subscriber).to receive(:respond_to?).with(:process).and_return(true)
      allow(working_subscriber).to receive(:respond_to?).with(:process).and_return(true)

      allow(error_subscriber).to receive(:process).and_raise(StandardError.new('Test error'))
      expect(working_subscriber).to receive(:process).with(event)
      allow(Rails.logger).to receive(:error)

      EventBus.subscribe('test_event', error_subscriber)
      EventBus.subscribe('test_event', working_subscriber)

      expect {
        EventBus.publish(event, async: false)
      }.not_to raise_error

      expect(Rails.logger).to have_received(:error).with(/Error dispatching event/)
    end

    # Legacy EventDispatchJob test removed as we're fully migrating to Rails Event Store
  end

  describe '#dispatch_event' do
    let(:event) { Event.create!(event_type: 'test_event', agent_activity: agent_activity, data: { foo: 'bar' }) }

    it 'dispatches to a handler with process method' do
      handler = double('Handler')
      allow(handler).to receive(:respond_to?).with(:process).and_return(true)
      expect(handler).to receive(:process).with(event)

      EventBus.register_handler('test_event', handler)
      EventBus.instance.dispatch_event(event)
    end

    # Legacy handle_event method test removed as we're fully migrating to Rails Event Store
  end
end
