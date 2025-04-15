require 'rails_helper'

RSpec.describe "Event schema validation", type: :model do
  let(:agent_activity) { create(:agent_activity) }

  before do
    # Clear any existing schemas
    EventSchemaRegistry.instance.instance_variable_set(:@schemas, {})

    # Register a test schema
    EventSchemaRegistry.register_schema(
      'test.validated_event',
      { required: [ 'message', 'level' ], optional: [ 'details' ] },
      description: 'Test event with validation'
    )
  end

  describe "schema validation" do
    it "creates event with valid data" do
      event = Event.new(
        event_type: 'test.validated_event',
        data: { message: 'Test message', level: 'info' },
        agent_activity: agent_activity
      )

      expect(event).to be_valid
    end

    it "fails validation with missing required fields" do
      event = Event.new(
        event_type: 'test.validated_event',
        data: { message: 'Test message' }, # missing 'level'
        agent_activity: agent_activity
      )

      expect(event).not_to be_valid
      expect(event.errors[:data]).to include('Missing required field: level')
    end

    it "passes validation with optional fields" do
      event = Event.new(
        event_type: 'test.validated_event',
        data: { message: 'Test message', level: 'info', details: 'Some details' },
        agent_activity: agent_activity
      )

      expect(event).to be_valid
    end

    it "passes validation for event types without schemas" do
      event = Event.new(
        event_type: 'unregistered.event',
        data: { arbitrary: 'data' },
        agent_activity: agent_activity
      )

      expect(event).to be_valid
    end
  end

  describe "Event.publish with schema validation" do
    it "publishes event with valid data" do
      event = Event.publish(
        'test.validated_event',
        { message: 'Test message', level: 'info' },
        { agent_activity_id: agent_activity.id }
      )

      expect(event).to be_persisted
      expect(event.event_type).to eq('test.validated_event')
    end

    it "returns nil when publishing with invalid data" do
      # Capture the log message
      expect(Rails.logger).to receive(:error).with(/Missing required fields for 'test.validated_event': level/)

      event = Event.publish(
        'test.validated_event',
        { message: 'Test message' }, # missing 'level'
        { agent_activity_id: agent_activity.id }
      )

      expect(event).to be_nil
    end
  end

  describe "has_schema? and schema methods" do
    let(:event) { Event.new(event_type: 'test.validated_event', agent_activity: agent_activity) }

    it "returns true for has_schema? when schema exists" do
      expect(event.has_schema?).to be true
    end

    it "returns schema for event type" do
      schema = event.schema
      expect(schema[:required]).to contain_exactly('message', 'level')
      expect(schema[:optional]).to contain_exactly('details')
    end

    it "returns false for has_schema? when schema doesn't exist" do
      event.event_type = 'unregistered.event'
      expect(event.has_schema?).to be false
    end
  end
end
