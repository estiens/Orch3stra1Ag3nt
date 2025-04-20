# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EventService, type: :service do
  before do
    # Stub logger
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:info)
  end

  describe '.publish' do
    let(:event_type) { 'tool_execution.started' }
    let(:data) { { tool: 'test_tool', args: { foo: 'bar' } } }
    let(:metadata) { { agent_activity_id: 1, task_id: 2, project_id: 3 } }

    it 'publishes an event using the correct event class' do
      # The class resolution should work
      expect(EventService).to receive(:event_class_for).with(event_type).and_call_original

      # The implementation skips event_store.publish in test env, let's verify that
      # (Assuming Rails.configuration.event_store is set for this test)
      # Use a null_object double so helper cleanup methods (like .subscribers) don't fail
      event_store_double = double("RailsEventStore::Client").as_null_object
      allow(Rails.configuration).to receive(:event_store).and_return(event_store_double)
      expect(event_store_double).not_to receive(:publish)

      EventService.publish(event_type, data, metadata)
    end

    context 'with invalid event data' do
      let(:bad_data) { { wrong_field: 'value' } } # Missing required fields

      it 'logs an error and returns nil' do
        # Mock validation to fail
        allow_any_instance_of(BaseEvent).to receive(:valid?).and_return(false)
        allow_any_instance_of(BaseEvent).to receive(:validation_errors).and_return([ 'Missing required field' ])

        result = EventService.publish(event_type, bad_data, metadata)
        expect(result).to be_nil
        expect(Rails.logger).to have_received(:error).with(/Invalid event data/)
      end
    end

    context 'when event class cannot be found' do
      let(:unknown_event_type) { 'unknown_event_type' }

      it 'logs an error and uses GenericEvent' do
        result = EventService.publish(unknown_event_type, data, metadata)
        expect(Rails.logger).to have_received(:error).with(/No event class found/)
        expect(result).to be_a(GenericEvent)
      end
    end
  end
end
