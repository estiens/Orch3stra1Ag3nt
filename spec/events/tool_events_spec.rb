# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Tool Events', type: :event do
  describe ToolEvents::ToolExecutionStartedEvent do
    let(:valid_data) { { tool: 'test_tool', args: { param: 'value' } } }
    let(:invalid_data) { { args: { param: 'value' } } } # Missing tool

    describe '.event_type' do
      it 'returns the correct event type' do
        expect(ToolEvents::ToolExecutionStartedEvent.event_type).to eq('tool_execution.started')
      end
    end

    describe '#valid?' do
      it 'returns true for valid data' do
        event = ToolEvents::ToolExecutionStartedEvent.new(data: valid_data)
        expect(event.valid?).to be true
      end

      it 'returns false for invalid data' do
        event = ToolEvents::ToolExecutionStartedEvent.new(data: invalid_data)
        expect(event.valid?).to be false
      end
    end

    describe '#validation_errors' do
      it 'returns an empty hash for valid data' do
        event = ToolEvents::ToolExecutionStartedEvent.new(data: valid_data)
        expect(event.validation_errors).to be_empty
      end

      it 'returns errors for invalid data' do
        event = ToolEvents::ToolExecutionStartedEvent.new(data: invalid_data)
        expect(event.validation_errors).not_to be_empty
        expect(event.validation_errors).to have_key(:tool)
      end
    end
  end

  describe ToolEvents::ToolExecutionFinishedEvent do
    let(:valid_data) { { tool: 'test_tool', result: 'success' } }
    let(:invalid_data) { { tool: 'test_tool' } } # Missing result

    describe '.event_type' do
      it 'returns the correct event type' do
        expect(ToolEvents::ToolExecutionFinishedEvent.event_type).to eq('tool_execution.finished')
      end
    end

    describe '#valid?' do
      it 'returns true for valid data' do
        event = ToolEvents::ToolExecutionFinishedEvent.new(data: valid_data)
        expect(event.valid?).to be true
      end

      it 'returns false for invalid data' do
        event = ToolEvents::ToolExecutionFinishedEvent.new(data: invalid_data)
        expect(event.valid?).to be false
      end
    end
  end

  describe ToolEvents::ToolExecutionErrorEvent do
    let(:valid_data) { { tool: 'test_tool', error: 'Something went wrong' } }
    let(:invalid_data) { { tool: 'test_tool' } } # Missing error

    describe '.event_type' do
      it 'returns the correct event type' do
        expect(ToolEvents::ToolExecutionErrorEvent.event_type).to eq('tool_execution.error')
      end
    end

    describe '#valid?' do
      it 'returns true for valid data' do
        event = ToolEvents::ToolExecutionErrorEvent.new(data: valid_data)
        expect(event.valid?).to be true
      end

      it 'returns false for invalid data' do
        event = ToolEvents::ToolExecutionErrorEvent.new(data: invalid_data)
        expect(event.valid?).to be false
      end
    end
  end
end
