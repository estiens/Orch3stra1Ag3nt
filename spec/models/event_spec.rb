require 'rails_helper'

RSpec.describe Event, type: :model do
  describe "associations" do
    it { should belong_to(:agent_activity) }
  end

  describe 'validations' do
    it 'requires an event_type' do
      event = Event.new(data: { foo: 'bar' })
      expect(event).not_to be_valid
      expect(event.errors[:event_type]).to include("can't be blank")
    end

    it 'requires data to be present' do
      event = Event.new(event_type: 'test_event')
      expect(event).not_to be_valid
      expect(event.errors[:data]).to include("can't be blank")
    end

    it 'is valid with both event_type and data' do
      event = Event.new(event_type: 'test_event', data: { foo: 'bar' })
      expect(event).to be_valid
    end
  end

  describe 'attributes' do
    it 'stores data as a hash' do
      data = { foo: 'bar', count: 42 }
      event = Event.create!(event_type: 'test_event', data: data)

      # Reload to ensure data is properly serialized/deserialized
      event.reload

      expect(event.data).to eq(data.stringify_keys)
      expect(event.data['foo']).to eq('bar')
      expect(event.data['count']).to eq(42)
    end
  end

  describe 'publishing' do
    it 'publishes itself to the EventBus after creation' do
      event = Event.new(event_type: 'test_event', data: { foo: 'bar' })

      expect(EventBus).to receive(:publish).with(event)
      event.save!
    end
  end

  describe '#to_s' do
    it 'returns a string representation with event type and ID' do
      event = Event.create!(event_type: 'test_event', data: { test: 'data' })
      expect(event.to_s).to eq("Event[#{event.id}] test_event")
    end
  end

  describe '.unprocessed' do
    it 'returns events that have not been processed' do
      processed = Event.create!(event_type: 'processed', data: {}, processed_at: Time.current)
      unprocessed = Event.create!(event_type: 'unprocessed', data: {})

      results = Event.unprocessed

      expect(results).to include(unprocessed)
      expect(results).not_to include(processed)
    end
  end

  describe '.mark_processed' do
    it 'updates the processed_at timestamp' do
      event = Event.create!(event_type: 'test', data: {})
      expect(event.processed_at).to be_nil

      event.mark_processed

      expect(event.processed_at).not_to be_nil
    end
  end

  describe '#process' do
    it 'dispatches the event via EventBus' do
      event = Event.create!(event_type: 'test_event', data: {})

      expect(EventBus.instance).to receive(:dispatch_event).with(event)

      event.process
    end

    it 'marks the event as processed' do
      event = Event.create!(event_type: 'test_event', data: {})

      allow(EventBus.instance).to receive(:dispatch_event)

      event.process

      expect(event.processed_at).not_to be_nil
    end
  end
end
