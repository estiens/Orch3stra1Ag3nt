# frozen_string_literal: true

module AgentEvents
  # AgentPausedEvent: Event triggered when an agent is paused during execution
  class AgentPausedEvent < BaseEvent
    SCHEMA = Dry::Schema.Params do
      required(:agent_type).filled(:string)
      required(:agent_id).filled(:string)
      optional(:reason).maybe(:string)
      optional(:pause_point).maybe(:string)
      optional(:initiated_by).maybe(:string)
    end

    def self.event_type
      "agent.paused"
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
