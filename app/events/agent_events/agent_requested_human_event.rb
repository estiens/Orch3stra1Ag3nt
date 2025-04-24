# frozen_string_literal: true

module AgentEvents
  # AgentRequestedHumanEvent: Event triggered when an agent requests human intervention
  class AgentRequestedHumanEvent < BaseEvent
    SCHEMA = Dry::Schema.Params do
      required(:agent_type).filled(:string)
      required(:agent_id).filled(:string)
      required(:request_type).filled(:string)
      required(:prompt).filled(:string)
      optional(:options).maybe(:array)
      optional(:context).maybe(:hash)
      optional(:priority).maybe(:integer)
      optional(:timeout_ms).maybe(:integer)
    end

    def self.event_type
      "agent.requested_human"
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
