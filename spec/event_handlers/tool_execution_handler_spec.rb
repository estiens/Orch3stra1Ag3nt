# frozen_string_literal: true

require 'rails_helper'

# Create simple event classes for testing
module ToolEvents
  class TestStartedEvent < BaseEvent
    def self.event_type
      'tool_execution.started'
    end

    def event_type
      'tool_execution.started'
    end
  end

  class TestFinishedEvent < BaseEvent
    def self.event_type
      'tool_execution.finished'
    end

    def event_type
      'tool_execution.finished'
    end
  end

  class TestErrorEvent < BaseEvent
    def self.event_type
      'tool_execution.error'
    end

    def event_type
      'tool_execution.error'
    end
  end
end

class UnknownEvent < BaseEvent
  def self.event_type
    'unknown_event'
  end

  def event_type
    'unknown_event'
  end
end

RSpec.describe ToolExecutionHandler, type: :event_handler do
  let(:handler) { ToolExecutionHandler.new }

  before do
    # Allow logging but don't actually log during tests
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:debug)
  end

  describe '#call' do
    context 'with a tool_execution.started event' do
      let(:event) do
        ToolEvents::TestStartedEvent.new(
          data: { tool: 'test_tool', args: { foo: 'bar' } },
          metadata: { agent_activity_id: 123 }
        )
      end

      it 'logs the tool start' do
        expect(Rails.logger).to receive(:info).with(/Started: test_tool/)
        handler.call(event)
      end
    end

    context 'with a tool_execution.finished event' do
      let(:event) do
        ToolEvents::TestFinishedEvent.new(
          data: { tool: 'test_tool', result: 'success' },
          metadata: { agent_activity_id: 123 }
        )
      end

      it 'logs the tool completion' do
        expect(Rails.logger).to receive(:info).with(/Finished: test_tool/)
        handler.call(event)
      end
    end

    context 'with a tool_execution.error event' do
      let(:event) do
        ToolEvents::TestErrorEvent.new(
          data: { tool: 'test_tool', error: 'Something went wrong' },
          metadata: { agent_activity_id: 123 }
        )
      end

      it 'logs the tool error' do
        expect(Rails.logger).to receive(:error).with(/Error: test_tool/)
        handler.call(event)
      end
    end

    context 'with an unknown event type' do
      let(:event) do
        UnknownEvent.new(
          data: { some: 'data' },
          metadata: { agent_activity_id: 123 }
        )
      end

      it 'logs that it received an unhandled event type' do
        allow(handler).to receive(:log_handler_activity)
        expect(handler).to receive(:log_handler_activity).with(event, 'Received unhandled event type')
        handler.call(event)
      end
    end
  end
end
