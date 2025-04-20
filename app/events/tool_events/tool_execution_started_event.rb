# frozen_string_literal: true

module ToolEvents
  class ToolExecutionStartedEvent < BaseEvent
    SCHEMA = Dry::Schema.Params do
      required(:tool).filled(:string)
      required(:args).value(:hash)
      optional(:context).value(:hash)
    end

    def self.event_type
      "tool_execution.started"
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
