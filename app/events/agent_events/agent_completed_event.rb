# frozen_string_literal: true

module AgentEvents
  # AgentCompletedEvent: Event triggered when an agent completes its execution
  class AgentCompletedEvent < BaseEvent
    SCHEMA = Dry::Schema.Params do
      required(:agent_type).filled(:string)
      required(:agent_id).filled(:string)
      required(:status).filled(:string)
      optional(:result).maybe(:hash)
      optional(:duration_ms).maybe(:integer)
    end

    def self.event_type
      "agent.completed"
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
