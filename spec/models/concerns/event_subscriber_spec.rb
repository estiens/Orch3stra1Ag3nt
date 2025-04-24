require 'rails_helper'

RSpec.describe EventSubscriber, type: :model do
  let(:subscriber_class) do
    Class.new do
      include EventSubscriber
      class << self
        attr_accessor :handled_events
      end

      def self.name
        'TestSubscriber'
      end

      # Define class-level handler for class .call
      def self.handle_class_event(event)
        @handled_events ||= []
        @handled_events << event
      end

      # Define instance-level handler
      attr_reader :handled_event
      def handle_instance_event(event)
        @handled_event = event
      end
    end
  end

  let(:instance) { subscriber_class.new }
  let(:event_double) { double('event', event_type: 'test.event', data: {}, metadata: {}) }

  describe '.subscribe_to' do
    before do
      subscriber_class.subscribe_to('test.event', :handle_class_event)
      subscriber_class.subscribe_to('block.event') { |ev| handle_class_event(ev) }
      subscriber_class.subscribe_to('instance.event', :handle_instance_event)
    end

    it 'registers method subscriptions' do
      expect(subscriber_class.event_subscriptions).to include(
        { event_type: 'test.event', method_name: :handle_class_event },
        { event_type: 'instance.event', method_name: :handle_instance_event }
      )
    end

    it 'registers block subscriptions' do
      expect(subscriber_class.event_subscriptions.any? { |sub| sub[:event_type] == 'block.event' && sub[:method_name].is_a?(Proc) }).to be true
    end
  end

  describe 'class-level .call' do
    it 'invokes class-level handler' do
      subscriber_class.subscriptions.clear
      subscriber_class.subscribe_to('class.event', :handle_class_event)
      subscriber_class.call(double('event', event_type: 'class.event'))
      expect(subscriber_class.instance_variable_get(:@handled_events)).to include(an_object_having_attributes(event_type: 'class.event'))
    end
  end

  describe 'instance-level call' do
    before do
      subscriber_class.subscriptions.clear
      subscriber_class.subscribe_to('instance.event', :handle_instance_event)
    end

    it 'invokes instance handler' do
      instance.call(double('event', event_type: 'instance.event'))
      expect(instance.handled_event).to have_attributes(event_type: 'instance.event')
    end
  end
end
