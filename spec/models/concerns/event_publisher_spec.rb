require 'rails_helper'

RSpec.describe EventPublisher, type: :model do
  let(:publishing_class) do
    Class.new do
      include EventPublisher
      def context
        { project_id: 10, task_id: 20, agent_activity_id: 30 }
      end
    end
  end

  let(:instance) { publishing_class.new }

  before do
    allow(EventMigrationExample).to receive(:map_legacy_to_new_event_type) { |ev| ev }
    allow(EventService).to receive(:publish).and_return(double('event'))
  end

  describe '#publish_event' do
    it 'publishes event with merged context metadata' do
      instance.publish_event('test.event', { foo: 'bar' })
      expect(EventService).to have_received(:publish).with(
        'test.event',
        { foo: 'bar' },
        hash_including(project_id: 10, task_id: 20, agent_activity_id: 30)
      )
    end

    it 'overrides context with explicit options' do
      instance.publish_event('test.event', { foo: 'bar' }, project_id: 99, priority: 5)
      expect(EventService).to have_received(:publish).with(
        'test.event',
        { foo: 'bar' },
        hash_including(project_id: 99, task_id: 20, agent_activity_id: 30, priority: 5)
      )
    end

    it 'returns nil and logs a warning if agent_activity_id is missing and not system_event' do
      allow(instance).to receive(:context).and_return({})
      expect(Rails.logger).to receive(:warn).with(/Cannot publish event/)
      expect(instance.publish_event('test.event', {})).to be_nil
    end

    it 'publishes system events even without agent_activity_id' do
      allow(instance).to receive(:context).and_return({})
      instance.publish_event('test.event', {}, system_event: true)
      expect(EventService).to have_received(:publish).with('test.event', {}, {})
    end
  end

  describe '.publish_event' do
    it 'delegates to EventService.publish' do
      publishing_class.publish_event('class.event', { data: true }, { custom: 1 })
      expect(EventService).to have_received(:publish).with('class.event', { data: true }, { custom: 1 })
    end
  end
end
