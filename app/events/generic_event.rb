# frozen_string_literal: true

# GenericEvent: Used when a specific event class can't be found
# Acts as a fallback for unknown event types
class GenericEvent < BaseEvent
  def self.event_type
    "generic_event"
  end
  
  def initialize(data: {}, metadata: {}, event_type: nil)
    super(data: data, metadata: metadata)
    @custom_event_type = event_type if event_type
  end
  
  def event_type
    @custom_event_type || self.class.event_type
  end
end