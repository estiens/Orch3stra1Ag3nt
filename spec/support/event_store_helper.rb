# frozen_string_literal: true

# Support for testing with Rails Event Store
module EventStoreHelper
  @@event_store = nil
  @@create_event_records = nil
  
  # Mock event store methods for RailsEventStore
  module EventStoreMock
    def self.included(base)
      # Override Rails.configuration.event_store and Rails.configuration.create_event_records
      # in the test environment only for classes that include this module
      
      base.class_eval do
        def self.event_store
          EventStoreHelper.event_store
        end
        
        def self.create_legacy_event_record
          # No-op for testing
          true
        end
      end
    end
  end
  
  # Class methods for the helper
  def self.event_store
    if @@event_store.nil?
      @@event_store = double('EventStore')
      allow(@@event_store).to receive(:publish).and_return(true)
      allow(@@event_store).to receive(:subscribe).and_return(true)
    end
    @@event_store
  end
  
  def self.create_event_records
    @@create_event_records ||= false
  end
  
  def self.create_event_records=(value)
    @@create_event_records = value
  end
  
  # Instance methods for the tests
  def setup_test_event_store
    # Allow BaseEvent to access event_store without Rails.configuration
    BaseEvent.send(:include, EventStoreMock)
    
    # Set create_event_records for the test
    EventStoreHelper.create_event_records = true
    
    # Stub Event creation 
    allow(Event).to receive(:create!).and_return(double('Event'))
  end
end

RSpec.configure do |config|
  config.include EventStoreHelper
end