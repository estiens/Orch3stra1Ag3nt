# frozen_string_literal: true

require 'rails_helper'

# Define TestEvent at the top level for use in specs
class TestEvent < BaseEvent
  def self.event_type
    'test_event'
  end
end

RSpec.describe BaseEvent, type: :event do
  # No before block needed since we're not using Event model anymore

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

  # Legacy event record creation tests are removed as we're fully migrating to Rails Event Store
end
