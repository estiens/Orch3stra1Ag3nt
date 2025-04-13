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
  end
end
