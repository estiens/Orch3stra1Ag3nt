require 'rails_helper'

RSpec.describe EventBus do
  # Reset singleton between tests
  before(:each) do
    EventBus.instance_variable_set(:@instance, nil)
  end

  after(:each) do
    EventBus.instance_variable_set(:@instance, nil)
  end

  describe '.instance' do
    it 'returns a singleton instance' do
      instance1 = EventBus.instance
      instance2 = EventBus.instance

      expect(instance1).to be_a(EventBus)
      expect(instance1).to equal(instance2)
    end
  end

  describe '#subscribe' do
    it 'registers a handler for an event type' do
      bus = EventBus.instance
      handler = double('handler')

      bus.subscribe('test_event', handler, :handle_test)

      subscribers = bus.instance_variable_get(:@subscribers)
      expect(subscribers['test_event']).to include([ handler, :handle_test ])
    end

    it 'allows multiple handlers for the same event type' do
      bus = EventBus.instance
      handler1 = double('handler1')
      handler2 = double('handler2')

      bus.subscribe('test_event', handler1, :handle_test1)
      bus.subscribe('test_event', handler2, :handle_test2)

      subscribers = bus.instance_variable_get(:@subscribers)
      expect(subscribers['test_event']).to include([ handler1, :handle_test1 ])
      expect(subscribers['test_event']).to include([ handler2, :handle_test2 ])
    end
  end

  describe '#publish' do
    let(:event_data) { { key: 'value' } }

    it 'creates an event record' do
      bus = EventBus.instance

      expect {
        bus.publish('test_event', event_data)
      }.to change(Event, :count).by(1)

      event = Event.last
      expect(event.event_type).to eq('test_event')
      expect(event.data).to eq(event_data.stringify_keys)
      expect(event.processed_at).to be_nil
    end

    it 'enqueues an EventDispatchJob' do
      bus = EventBus.instance

      expect {
        bus.publish('test_event', event_data)
      }.to have_enqueued_job(EventDispatchJob)
    end

    it 'immediately dispatches the event when sync: true' do
      bus = EventBus.instance
      event_id = nil

      # It should not enqueue a job
      expect {
        event_id = bus.publish('test_event', event_data, sync: true)
      }.not_to have_enqueued_job(EventDispatchJob)

      # But it should mark the event as processed
      event = Event.find(event_id)
      expect(event.processed_at).not_to be_nil
    end
  end

  describe '#dispatch_event' do
    let(:handler) { double('handler') }
    let(:event) { Event.create!(event_type: 'test_event', data: { key: 'value' }) }

    before do
      bus = EventBus.instance
      bus.subscribe('test_event', handler, :handle_test)
    end

    it 'calls the registered handler method with the event' do
      expect(handler).to receive(:handle_test).with(event)

      EventBus.instance.dispatch_event(event)
    end

    it 'handles multiple subscribers' do
      handler2 = double('handler2')
      EventBus.instance.subscribe('test_event', handler2, :handle_test2)

      expect(handler).to receive(:handle_test).with(event)
      expect(handler2).to receive(:handle_test2).with(event)

      EventBus.instance.dispatch_event(event)
    end

    it 'logs errors but continues processing subscribers' do
      handler2 = double('handler2')
      EventBus.instance.subscribe('test_event', handler2, :handle_test2)

      # First handler raises an error
      expect(handler).to receive(:handle_test).and_raise("Test error")
      # Second handler should still be called
      expect(handler2).to receive(:handle_test2).with(event)

      # It should log the error
      expect(Rails.logger).to receive(:error).with(/Error handling event test_event/).at_least(:once)

      # But not raise
      expect {
        EventBus.instance.dispatch_event(event)
      }.not_to raise_error
    end

    it 'does nothing for an event type with no subscribers' do
      event = Event.create!(event_type: 'unknown_event', data: {})

      # Should not raise an error
      expect {
        EventBus.instance.dispatch_event(event)
      }.not_to raise_error
    end
  end

  describe '#subscribers_for' do
    it 'returns all subscribers for a given event type' do
      bus = EventBus.instance
      handler1 = double('handler1')
      handler2 = double('handler2')

      bus.subscribe('test_event', handler1, :handle_test1)
      bus.subscribe('test_event', handler2, :handle_test2)

      subscribers = bus.subscribers_for('test_event')
      expect(subscribers).to include([ handler1, :handle_test1 ])
      expect(subscribers).to include([ handler2, :handle_test2 ])
    end

    it 'returns an empty array for an event type with no subscribers' do
      bus = EventBus.instance
      subscribers = bus.subscribers_for('unknown_event')
      expect(subscribers).to eq([])
    end
  end
end
