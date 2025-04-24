# frozen_string_literal: true

module SystemEvents
  # SystemConfigChangedEvent: Event triggered when system configuration changes
  class SystemConfigChangedEvent < BaseEvent
    SCHEMA = Dry::Schema.Params do
      required(:component).filled(:string)
      required(:changes).filled(:hash)
      optional(:user_id).maybe(:string)
      optional(:previous_config).maybe(:hash)
      optional(:current_config).maybe(:hash)
    end

    def self.event_type
      "system.config_changed"
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
