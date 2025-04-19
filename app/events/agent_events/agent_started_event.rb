# frozen_string_literal: true

module AgentEvents
  # AgentStartedEvent: Event triggered when an agent starts its execution
  class AgentStartedEvent < BaseEvent
    SCHEMA = Dry::Schema.Params do
      required(:agent_type).filled(:string)
      required(:agent_id).filled(:string)
      optional(:purpose).maybe(:string)
      optional(:config).maybe(:hash)
    end

    def self.event_type
      "agent.started"
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
