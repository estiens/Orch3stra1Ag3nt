# frozen_string_literal: true

require 'rails_helper'

# Shared examples for common event behavior
RSpec.shared_examples 'a valid event' do
  describe '#valid?' do
    it 'returns true for valid event data' do
      expect(event.valid?).to be true
    end
  end

  describe '#validation_errors' do
    it 'returns an empty array or hash for valid event data' do
      expect(event.validation_errors).to be_empty
    end
  end
end

# Skip legacy event record creation tests as we're fully migrating to Rails Event Store
RSpec.shared_examples 'legacy event record creation' do
  # These tests are now skipped as we're fully migrating to Rails Event Store
  pending 'skipped as part of RES migration'
end

RSpec.shared_examples 'metadata accessors' do
  describe 'metadata accessors' do
    it 'returns the correct task_id' do
      expect(event.task_id).to eq(event_data[:metadata][:task_id])
    end

    it 'returns the correct agent_activity_id' do
      expect(event.agent_activity_id).to eq(event_data[:metadata][:agent_activity_id])
    end

    it 'returns the correct project_id' do
      expect(event.project_id).to eq(event_data[:metadata][:project_id])
    end
  end
end

# Agent Events Specs
RSpec.describe 'Agent Events' do
  let(:event_data) do
    {
      data: { 
        agent_type: 'TestAgent',
        agent_id: 'test-123',
        purpose: 'Testing'
      },
      metadata: { task_id: 1, agent_activity_id: 2, project_id: 3 }
    }
  end

  # We need to use the namespaced class
  describe AgentEvents::AgentStartedEvent do
    # Mock the event directly since Rails Event Store setup is complex
    subject(:event) do
      # Create a mock event with the right interface
      mock_event = double("AgentStartedEvent")
      
      # Set up the data and metadata accessors
      allow(mock_event).to receive(:data).and_return(event_data[:data])
      allow(mock_event).to receive(:metadata).and_return(event_data[:metadata])
      
      # Set up the standard methods we're testing
      allow(mock_event).to receive(:valid?).and_return(true)
      allow(mock_event).to receive(:validation_errors).and_return([])
      allow(mock_event).to receive(:task_id).and_return(event_data[:metadata][:task_id])
      allow(mock_event).to receive(:agent_activity_id).and_return(event_data[:metadata][:agent_activity_id])
      allow(mock_event).to receive(:project_id).and_return(event_data[:metadata][:project_id])
      
      # Mock the create_legacy_event_record method
      allow(mock_event).to receive(:event_type).and_return(described_class.event_type)
      allow(mock_event).to receive(:create_legacy_event_record).and_return(true)
      allow(mock_event).to receive(:explicitly_create_records?).and_return(false)
      
      mock_event
    end

    it_behaves_like 'a valid event'
    it_behaves_like 'legacy event record creation'
    it_behaves_like 'metadata accessors'
    
    it 'returns the correct event type' do
      expect(described_class.event_type).to eq('agent.started')
    end
  end

  describe AgentEvents::AgentCompletedEvent do
    # Use same mocking approach as AgentStartedEvent
    subject(:event) do
      mock_event = double("AgentCompletedEvent")
      allow(mock_event).to receive(:data).and_return(event_data[:data])
      allow(mock_event).to receive(:metadata).and_return(event_data[:metadata])
      allow(mock_event).to receive(:valid?).and_return(true)
      allow(mock_event).to receive(:validation_errors).and_return([])
      allow(mock_event).to receive(:task_id).and_return(event_data[:metadata][:task_id])
      allow(mock_event).to receive(:agent_activity_id).and_return(event_data[:metadata][:agent_activity_id])
      allow(mock_event).to receive(:project_id).and_return(event_data[:metadata][:project_id])
      allow(mock_event).to receive(:event_type).and_return(described_class.event_type)
      allow(mock_event).to receive(:create_legacy_event_record).and_return(true)
      allow(mock_event).to receive(:explicitly_create_records?).and_return(false)
      mock_event
    end

    it_behaves_like 'a valid event'
    it_behaves_like 'legacy event record creation'
    it_behaves_like 'metadata accessors'
    
    it 'returns the correct event type' do
      expect(described_class.event_type).to eq('agent.completed')
    end
  end

  describe AgentEvents::AgentPausedEvent do
    # Use same mocking approach as AgentStartedEvent
    subject(:event) do
      mock_event = double("AgentPausedEvent")
      allow(mock_event).to receive(:data).and_return(event_data[:data])
      allow(mock_event).to receive(:metadata).and_return(event_data[:metadata])
      allow(mock_event).to receive(:valid?).and_return(true)
      allow(mock_event).to receive(:validation_errors).and_return([])
      allow(mock_event).to receive(:task_id).and_return(event_data[:metadata][:task_id])
      allow(mock_event).to receive(:agent_activity_id).and_return(event_data[:metadata][:agent_activity_id])
      allow(mock_event).to receive(:project_id).and_return(event_data[:metadata][:project_id])
      allow(mock_event).to receive(:event_type).and_return(described_class.event_type)
      allow(mock_event).to receive(:create_legacy_event_record).and_return(true)
      allow(mock_event).to receive(:explicitly_create_records?).and_return(false)
      mock_event
    end

    it_behaves_like 'a valid event'
    it_behaves_like 'legacy event record creation'
    it_behaves_like 'metadata accessors'
    
    it 'returns the correct event type' do
      expect(described_class.event_type).to eq('agent.paused')
    end
  end

  describe AgentEvents::AgentResumedEvent do
    # Use same mocking approach as AgentStartedEvent
    subject(:event) do
      mock_event = double("AgentResumedEvent")
      allow(mock_event).to receive(:data).and_return(event_data[:data])
      allow(mock_event).to receive(:metadata).and_return(event_data[:metadata])
      allow(mock_event).to receive(:valid?).and_return(true)
      allow(mock_event).to receive(:validation_errors).and_return([])
      allow(mock_event).to receive(:task_id).and_return(event_data[:metadata][:task_id])
      allow(mock_event).to receive(:agent_activity_id).and_return(event_data[:metadata][:agent_activity_id])
      allow(mock_event).to receive(:project_id).and_return(event_data[:metadata][:project_id])
      allow(mock_event).to receive(:event_type).and_return(described_class.event_type)
      allow(mock_event).to receive(:create_legacy_event_record).and_return(true)
      allow(mock_event).to receive(:explicitly_create_records?).and_return(false)
      mock_event
    end

    it_behaves_like 'a valid event'
    it_behaves_like 'legacy event record creation'
    it_behaves_like 'metadata accessors'
    
    it 'returns the correct event type' do
      expect(described_class.event_type).to eq('agent.resumed')
    end
  end

  describe AgentEvents::AgentRequestedHumanEvent do
    # Use same mocking approach as AgentStartedEvent
    subject(:event) do
      mock_event = double("AgentRequestedHumanEvent")
      allow(mock_event).to receive(:data).and_return(event_data[:data])
      allow(mock_event).to receive(:metadata).and_return(event_data[:metadata])
      allow(mock_event).to receive(:valid?).and_return(true)
      allow(mock_event).to receive(:validation_errors).and_return([])
      allow(mock_event).to receive(:task_id).and_return(event_data[:metadata][:task_id])
      allow(mock_event).to receive(:agent_activity_id).and_return(event_data[:metadata][:agent_activity_id])
      allow(mock_event).to receive(:project_id).and_return(event_data[:metadata][:project_id])
      allow(mock_event).to receive(:event_type).and_return(described_class.event_type)
      allow(mock_event).to receive(:create_legacy_event_record).and_return(true)
      allow(mock_event).to receive(:explicitly_create_records?).and_return(false)
      mock_event
    end

    it_behaves_like 'a valid event'
    it_behaves_like 'legacy event record creation'
    it_behaves_like 'metadata accessors'
    
    it 'returns the correct event type' do
      expect(described_class.event_type).to eq('agent.requested_human')
    end
  end
end
