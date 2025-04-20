# frozen_string_literal: true

module TaskEvents
  class TaskFailedEvent < BaseEvent
    data_schema do
      required(:task_id).filled(:integer)
      required(:task_title).filled(:string)
      optional(:error_message).maybe(:string) # Optional error message
    end

    # Override event_type to provide a specific type name
    def self.event_type
      "task.failed"
    end
  end
end
