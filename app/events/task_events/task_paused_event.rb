# frozen_string_literal: true

module TaskEvents
  class TaskPausedEvent < BaseEvent
    data_schema do
      required(:task_id).filled(:integer)
      required(:task_title).filled(:string)
    end

    # Override event_type to provide a specific type name
    def self.event_type
      "task.paused"
    end
  end
end
