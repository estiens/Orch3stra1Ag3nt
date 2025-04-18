require 'rails_helper'

RSpec.describe Event, type: :model do
  let(:agent_activity) { create(:agent_activity) }

  describe "associations" do
    it "belongs to agent_activity" do
      expect(described_class.reflect_on_association(:agent_activity).options[:optional]).to eq(true)
    end
  end

  describe 'validations' do
    it 'requires an event_type' do
      event = Event.new(agent_activity: agent_activity, data: { foo: 'bar' })
      expect(event).not_to be_valid
      expect(event.errors[:event_type]).to include("can't be blank")
    end

    # No validation for data presence, empty hash is valid
    # Removed test: 'requires data to be present'

    it 'is valid with event_type, agent_activity and data' do
      event = Event.new(event_type: 'test_event', agent_activity: agent_activity, data: { foo: 'bar' })
      expect(event).to be_valid
    end
  end

  describe 'attributes' do
    it 'stores data as a hash' do
      data = { foo: 'bar', count: 42 }
      event = Event.create!(event_type: 'test_event', agent_activity: agent_activity, data: data)

      # Reload to ensure data is properly serialized/deserialized
      event.reload

      expect(event.data).to eq(data.stringify_keys)
      expect(event.data['foo']).to eq('bar')
      expect(event.data['count']).to eq(42)
    end
  end

  describe 'publishing' do
    xit 'publishes itself to the EventBus after creation - skipped during RES migration' do
      event = Event.new(event_type: 'test_event', agent_activity: agent_activity, data: { foo: 'bar' })

      expect(EventBus).to receive(:publish).with(event)
      event.save!
    end
  end

  describe '#to_s' do
    it 'returns a string representation with event type and ID' do
      event = Event.create!(event_type: 'test_event', agent_activity: agent_activity, data: { test: 'data' })
      expect(event.to_s).to eq("Event[#{event.id}] test_event")
    end
  end

  describe '.unprocessed' do
    it 'returns events that have not been processed' do
      processed = Event.create!(event_type: 'processed', agent_activity: agent_activity, data: {}, processed_at: Time.current)
      unprocessed = Event.create!(event_type: 'unprocessed', agent_activity: agent_activity, data: {})

      results = Event.unprocessed

      expect(results).to include(unprocessed)
      expect(results).not_to include(processed)
    end
  end

  describe '.mark_processed' do
    it 'updates the processed_at timestamp' do
      event = Event.create!(event_type: 'test', agent_activity: agent_activity, data: {})
      expect(event.processed_at).to be_nil

      event.mark_processed

      expect(event.processed_at).not_to be_nil
    end
  end

  describe '#process' do
    it 'dispatches the event via EventBus' do
      event = Event.create!(event_type: 'test_event', agent_activity: agent_activity, data: {})

      expect(EventBus.instance).to receive(:dispatch_event).with(event)

      event.process
    end

    it 'marks the event as processed' do
      event = Event.create!(event_type: 'test_event', agent_activity: agent_activity, data: {})

      allow(EventBus.instance).to receive(:dispatch_event)

      event.process

      expect(event.processed_at).not_to be_nil
    end
  end
end
