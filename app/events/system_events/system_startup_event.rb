# frozen_string_literal: true

module SystemEvents
  # SystemStartupEvent: Event triggered when the system starts up
  class SystemStartupEvent < BaseEvent
    SCHEMA = Dry::Schema.Params do
      required(:version).filled(:string)
      required(:environment).filled(:string)
      optional(:boot_time_ms).maybe(:integer)
      optional(:config).maybe(:hash)
    end

    def self.event_type
      "system.startup"
    end

    def valid?
      errors = validation_errors
      errors.empty?
    end

    def validation_errors
      SCHEMA.call(data).errors.to_h
    end
  end
end
