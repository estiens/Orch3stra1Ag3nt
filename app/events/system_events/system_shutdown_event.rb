# frozen_string_literal: true

module SystemEvents
  # SystemShutdownEvent: Event triggered when the system is shutting down
  class SystemShutdownEvent < BaseEvent
    SCHEMA = Dry::Schema.Params do
      required(:reason).filled(:string)
      required(:exit_code).filled(:integer)
      optional(:uptime_ms).maybe(:integer)
      optional(:stats).maybe(:hash)
    end

    def self.event_type
      "system.shutdown"
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
