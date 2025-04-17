# frozen_string_literal: true

require 'rails_helper'

# Define TestEvent at the top level for use in specs
class TestEvent < BaseEvent
  def self.event_type
    'test_event'
  end
end

RSpec.describe BaseEvent, type: :event do
  before do
    # Stub Event creation
    allow(Event).to receive(:create!).and_return(double('Event'))
  end

  describe 'metadata accessors' do
    let(:metadata) do
      {
        task_id: 123,
        agent_activity_id: 456,
        project_id: 789
      }
    end
    
    let(:event) { TestEvent.new(data: {}, metadata: metadata) }

    it 'provides access to task_id' do
      expect(event.task_id).to eq(123)
    end

    it 'provides access to agent_activity_id' do
      expect(event.agent_activity_id).to eq(456)
    end

    it 'provides access to project_id' do
      expect(event.project_id).to eq(789)
    end

    it 'returns nil for missing metadata' do
      event = TestEvent.new(data: {}, metadata: {})
      expect(event.task_id).to be_nil
      expect(event.agent_activity_id).to be_nil
      expect(event.project_id).to be_nil
    end
  end

  describe '#valid?' do
    it 'returns true for base validation' do
      event = BaseEvent.new(data: {})
      expect(event.valid?).to be true
    end
  end

  describe '#validation_errors' do
    it 'returns an empty array for base validation' do
      event = BaseEvent.new(data: {})
      expect(event.validation_errors).to eq([])
    end
  end

  describe '#create_legacy_event_record' do
    let(:event) do
      TestEvent.new(
        data: { key: 'value' },
        metadata: { task_id: 123, agent_activity_id: 456, project_id: 789 }
      )
    end

    context 'when creating records is enabled' do
      it 'creates an Event record with the correct attributes' do
        event.create_records_override = true
        
        expect(Event).to receive(:create!).with(
          event_type: 'TestEvent',
          data: { key: 'value' },
          agent_activity_id: 456,
          task_id: 123,
          project_id: 789
        )
        
        event.create_legacy_event_record
      end
    end

    context 'when creating records is disabled' do
      it 'does not create an Event record' do
        # By default in tests, this is false
        expect(Event).not_to receive(:create!)
        event.create_legacy_event_record
      end
    end
  end
end