require 'rails_helper'

RSpec.describe EventDispatchJob, type: :job do
  include ActiveJob::TestHelper

  describe '#perform' do
    let(:event) { Event.create!(event_type: 'test_event', data: { foo: 'bar' }) }

    it 'processes the event' do
      expect_any_instance_of(Event).to receive(:process)

      EventDispatchJob.perform_now(event.id)
    end

    context 'when the event is not found' do
      it 'logs an error and does not raise an exception' do
        allow(Rails.logger).to receive(:error)

        expect {
          EventDispatchJob.perform_now(-1)
        }.not_to raise_error

        expect(Rails.logger).to have_received(:error).with(/Could not find Event with ID -1/)
      end
    end

    context 'when processing raises an error' do
      before do
        allow_any_instance_of(Event).to receive(:process).and_raise(StandardError.new("Test error"))
        allow(Rails.logger).to receive(:error)
      end

      it 'logs the error and does not raise an exception' do
        expect {
          EventDispatchJob.perform_now(event.id)
        }.not_to raise_error

        expect(Rails.logger).to have_received(:error).with(/Error processing event/)
      end
    end
  end

  describe '.perform_later' do
    let(:event) { Event.create!(event_type: 'test_event', data: { foo: 'bar' }) }

    it 'enqueues the job' do
      expect {
        EventDispatchJob.perform_later(event.id)
      }.to have_enqueued_job(EventDispatchJob).with(event.id)
    end
  end
end
