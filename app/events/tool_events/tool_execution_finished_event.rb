# frozen_string_literal: true

module ToolEvents
  class ToolExecutionFinishedEvent < BaseEvent
    SCHEMA = Dry::Schema.Params do
      required(:tool).filled(:string)
      required(:result).filled
      optional(:duration).filled(:float)
      optional(:metrics).value(:hash)
    end

    def self.event_type
      "tool_execution.finished"
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
