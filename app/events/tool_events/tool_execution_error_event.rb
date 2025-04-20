# frozen_string_literal: true

module ToolEvents
  class ToolExecutionErrorEvent < BaseEvent
    SCHEMA = Dry::Schema.Params do
      required(:tool).filled(:string)
      required(:error).filled(:string)
      optional(:args).value(:hash)
      optional(:stack_trace).filled(:string)
    end

    def self.event_type
      "tool_execution.error"
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
