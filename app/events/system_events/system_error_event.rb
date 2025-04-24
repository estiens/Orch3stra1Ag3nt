# frozen_string_literal: true

module SystemEvents
  # SystemErrorEvent: Event triggered when a system-level error occurs
  class SystemErrorEvent < BaseEvent
    SCHEMA = Dry::Schema.Params do
      required(:error_type).filled(:string)
      required(:message).filled(:string)
      optional(:backtrace).maybe(:array)
      optional(:component).maybe(:string)
      optional(:severity).maybe(:string)
      optional(:context).maybe(:hash)
    end

    def self.event_type
      "system.error"
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
