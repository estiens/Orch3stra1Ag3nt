require 'rails_helper'

RSpec.describe EventSchemaRegistry do
  before(:each) do
    # Clear any existing schemas before each test
    EventSchemaRegistry.instance.instance_variable_set(:@schemas, {})
  end

  describe '.register_schema' do
    it 'registers a new schema' do
      EventSchemaRegistry.register_schema(
        'test.event',
        { required: [ 'name' ], optional: [ 'description' ] },
        description: 'Test event schema'
      )

      expect(EventSchemaRegistry.schema_exists?('test.event')).to be true
    end

    it 'returns true when registration succeeds' do
      result = EventSchemaRegistry.register_schema('test.event', {})
      expect(result).to be true
    end
  end

  describe '.schema_exists?' do
    it 'returns true when schema exists' do
      EventSchemaRegistry.register_schema('test.event', {})
      expect(EventSchemaRegistry.schema_exists?('test.event')).to be true
    end

    it 'returns false when schema does not exist' do
      expect(EventSchemaRegistry.schema_exists?('nonexistent.event')).to be false
    end
  end

  describe '.schema_for' do
    it 'returns the schema for an event type' do
      schema_data = { required: [ 'name' ], optional: [ 'description' ] }
      EventSchemaRegistry.register_schema('test.event', schema_data, description: 'Test event')

      schema = EventSchemaRegistry.schema_for('test.event')
      expect(schema[:required]).to eq([ 'name' ])
      expect(schema[:optional]).to eq([ 'description' ])
      expect(schema[:description]).to eq('Test event')
    end

    it 'returns nil for nonexistent schema' do
      expect(EventSchemaRegistry.schema_for('nonexistent.event')).to be_nil
    end
  end

  describe '.validate_event' do
    let(:event) { instance_double(BaseEvent, event_type: 'test.event', data: { 'name' => 'Test' }) }

    before do
      EventSchemaRegistry.register_schema(
        'test.event',
        { required: [ 'name', 'timestamp' ], optional: [ 'description' ] }
      )
    end

    it 'returns empty array for valid event' do
      allow(event).to receive(:data).and_return({ 'name' => 'Test', 'timestamp' => Time.current })
      errors = EventSchemaRegistry.validate_event(event)
      expect(errors).to be_empty
    end

    it 'returns errors for missing required fields' do
      allow(event).to receive(:data).and_return({ 'name' => 'Test' })
      errors = EventSchemaRegistry.validate_event(event)
      expect(errors).to include('Missing required field: timestamp')
    end

    it 'handles both string and symbol keys in data' do
      allow(event).to receive(:data).and_return({ name: 'Test', timestamp: Time.current })
      errors = EventSchemaRegistry.validate_event(event)
      expect(errors).to be_empty
    end

    it 'returns warning for nonexistent schema' do
      allow(event).to receive(:event_type).and_return('nonexistent.event')

      # Capture the log message
      expect(Rails.logger).to receive(:warn).with(/No schema registered for event type: nonexistent.event/)

      errors = EventSchemaRegistry.validate_event(event)
      expect(errors).to be_empty
    end
  end

  describe '.registered_schemas' do
    it 'returns all registered schemas' do
      EventSchemaRegistry.register_schema('test.event1', { required: [ 'name' ] })
      EventSchemaRegistry.register_schema('test.event2', { required: [ 'id' ] })

      schemas = EventSchemaRegistry.registered_schemas
      expect(schemas.keys).to contain_exactly('test.event1', 'test.event2')
    end
  end
end
