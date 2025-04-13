require 'rails_helper'

class TestSubscriber
  include EventSubscriber

  subscribe_to 'test_event'

  def self.process(event)
    # Implementation for testing
  end
end

class MultiEventSubscriber
  include EventSubscriber

  subscribe_to 'event_one', 'event_two'

  def self.process(event)
    # Implementation for testing
  end
end

RSpec.describe EventSubscriber do
  after do
    # Clean up subscriptions after tests
    EventBus.instance_variable_set(:@subscribers, {})
  end

  describe '.subscribe_to' do
    it 'registers the class with EventBus for specified event types' do
      # Create a test class that includes EventSubscriber
      class TestSubscriber
        include EventSubscriber

        subscribe_to 'test_event'

        def self.process(event)
          # Processing logic
        end
      end

      expect(EventBus.subscribers_for('test_event')).to include(TestSubscriber)
    end

    it 'can register for multiple event types' do
      class MultiEventSubscriber
        include EventSubscriber

        subscribe_to 'event_one', 'event_two'

        def self.process(event)
          # Processing logic
        end
      end

      expect(EventBus.subscribers_for('event_one')).to include(MultiEventSubscriber)
      expect(EventBus.subscribers_for('event_two')).to include(MultiEventSubscriber)
    end

    it 'requires the class to implement process method' do
      expect {
        class InvalidSubscriber
          include EventSubscriber

          subscribe_to 'invalid_event'

          # Missing process method
        end
      }.to raise_error(NotImplementedError)
    end

    it 'allows multiple subscribers to listen to the same event' do
      class FirstSubscriber
        include EventSubscriber

        subscribe_to 'shared_event'

        def self.process(event)
          # Processing logic
        end
      end

      class SecondSubscriber
        include EventSubscriber

        subscribe_to 'shared_event'

        def self.process(event)
          # Processing logic
        end
      end

      subscribers = EventBus.subscribers_for('shared_event')
      expect(subscribers).to include(FirstSubscriber)
      expect(subscribers).to include(SecondSubscriber)
    end
  end

  describe 'processing' do
    let(:event) { Event.create!(event_type: 'test_event', data: { foo: 'bar' }) }

    it 'processes events via the EventBus' do
      expect(TestSubscriber).to receive(:process).with(event)
      EventBus.publish(event)
    end

    it 'only receives events it subscribed to' do
      other_event = Event.create!(event_type: 'unsubscribed_event', data: { baz: 'qux' })

      expect(TestSubscriber).not_to receive(:process)
      EventBus.publish(other_event)
    end
  end
end
