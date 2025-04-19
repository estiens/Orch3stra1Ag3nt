# frozen_string_literal: true

module AgentEvents
  # AgentResumedEvent: Event triggered when an agent resumes or unpauses its execution
  class AgentResumedEvent < BaseEvent
    SCHEMA = Dry::Schema.Params do
      required(:agent_type).filled(:string)
      required(:agent_id).filled(:string)
      optional(:pause_duration_ms).maybe(:integer)
      optional(:initiated_by).maybe(:string)
      optional(:resume_context).maybe(:hash)
    end

    def self.event_type
      "agent.resumed"
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
