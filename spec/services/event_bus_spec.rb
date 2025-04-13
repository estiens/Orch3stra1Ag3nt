require 'rails_helper'

RSpec.describe EventBus do
  describe '.subscribe' do
    after do
      # Clean up subscriptions after tests
      EventBus.instance_variable_set(:@subscribers, {})
    end

    it 'registers a subscriber for an event type' do
      test_subscriber = Class.new do
        def self.process(event)
          # Test subscriber
        end
      end

      EventBus.subscribe('test_event', test_subscriber)

      subscribers = EventBus.instance_variable_get(:@subscribers)
      expect(subscribers['test_event']).to include(test_subscriber)
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

      subscribers = EventBus.instance_variable_get(:@subscribers)
      expect(subscribers['test_event']).to include(test_subscriber1, test_subscriber2)
    end
  end

  describe '.publish' do
    let(:event) { Event.create!(event_type: 'test_event', data: { foo: 'bar' }) }

    after do
      # Clean up subscriptions after tests
      EventBus.instance_variable_set(:@subscribers, {})
    end

    it 'notifies all subscribers for the event type' do
      test_subscriber1 = double('Subscriber1')
      test_subscriber2 = double('Subscriber2')

      expect(test_subscriber1).to receive(:process).with(event)
      expect(test_subscriber2).to receive(:process).with(event)

      EventBus.subscribe('test_event', test_subscriber1)
      EventBus.subscribe('test_event', test_subscriber2)

      EventBus.publish(event)
    end

    it 'does not notify subscribers for other event types' do
      test_subscriber = double('Subscriber')

      expect(test_subscriber).not_to receive(:process)

      EventBus.subscribe('other_event', test_subscriber)

      EventBus.publish(event)
    end

    it 'handles errors from subscribers without affecting other subscribers' do
      error_subscriber = double('ErrorSubscriber')
      working_subscriber = double('WorkingSubscriber')

      allow(error_subscriber).to receive(:process).and_raise(StandardError.new('Test error'))
      expect(working_subscriber).to receive(:process).with(event)
      allow(Rails.logger).to receive(:error)

      EventBus.subscribe('test_event', error_subscriber)
      EventBus.subscribe('test_event', working_subscriber)

      expect {
        EventBus.publish(event)
      }.not_to raise_error

      expect(Rails.logger).to have_received(:error).with(/Error processing event/)
    end
  end
end
