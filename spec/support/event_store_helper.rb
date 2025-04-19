# frozen_string_literal: true

# Helper module for testing with Rails Event Store
module EventStoreHelper
  # Configure a real test instance of Rails Event Store
  def self.configure_test_event_store
    # Create a simple mock object for event_store
    require 'rspec/mocks'
    test_event_store = Object.new
    def test_event_store.publish(*args); true; end
    def test_event_store.subscribe(*args); true; end
    def test_event_store.subscribers; []; end
    def test_event_store.unsubscribe(*args); true; end

    # Set this as the Rails.configuration.event_store for tests
    Rails.configuration.event_store = test_event_store

    # Configuration flag for legacy events - we'll stub Event.create! separately
    Rails.configuration.create_event_records = true

    # Return the event store for test assertions
    test_event_store
  end

  # Reset everything between tests
  def self.reset
    # Clear all subscriptions if event store is configured
    if defined?(Rails.configuration.event_store) && !Rails.configuration.event_store.nil?
      Rails.configuration.event_store.tap do |es|
        es.subscribers.each { |sub| es.unsubscribe(sub) } rescue nil
      end
    end
  end

  # Instance methods for the tests
  def setup_test_event_store
    # Ensure we have an event store configured
    EventStoreHelper.configure_test_event_store if Rails.configuration.event_store.nil?
    
    # Stub Event creation for legacy compatibility
    allow(Event).to receive(:create!).and_return(double('Event'))
  end
end

# Configure the test event store before test execution
RSpec.configure do |config|
  config.include EventStoreHelper
  
  config.before(:suite) do
    begin
      EventStoreHelper.configure_test_event_store
    rescue => e
      puts "Error setting up EventStoreHelper: #{e.message}"
    end
  end

  config.after(:each) do
    begin
      EventStoreHelper.reset
    rescue => e
      puts "Error in EventStoreHelper.reset: #{e.message}"
    end
  end
end