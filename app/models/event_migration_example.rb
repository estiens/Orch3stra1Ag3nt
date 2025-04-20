# frozen_string_literal: true

# This module provides mapping between legacy event types and new dot-notation event types
# It's used during the transition period from the old event system to the new one
module EventMigrationExample
  # Map legacy underscore event types to new dot-notation event types
  def self.map_legacy_to_new_event_type(legacy_event_type)
    mapping = {
      # Task events
      "task_created" => "task.created",
      "task_activated" => "task.activated",
      "task_completed" => "task.completed",
      "task_failed" => "task.failed",
      "task_paused" => "task.paused",
      "task_resumed" => "task.resumed",

      # Project events
      "project_created" => "project.created",
      "project_activated" => "project.activated",
      "project_completed" => "project.completed",
      "project_paused" => "project.paused",
      "project_resumed" => "project.resumed",

      # Agent events
      "agent_started" => "agent.started",
      "agent_completed" => "agent.completed",
      "agent_failed" => "agent.failed",

      # Research events
      "code_research_task" => "code_research.task",
      "code_discovery" => "code_research.discovery",
      "research_findings" => "research.findings",

      # Human interaction events
      "human_input_requested" => "human_input.requested",
      "human_input_provided" => "human_input.provided",
      "human_input_processed" => "human_input.processed"

      # Default case: return the original event type if no mapping exists
    }

    mapping[legacy_event_type] || legacy_event_type
  end

  # Map new dot-notation event types to legacy underscore event types
  def self.map_new_to_legacy_event_type(new_event_type)
    mapping = {
      # Task events
      "task.created" => "task_created",
      "task.activated" => "task_activated",
      "task.completed" => "task_completed",
      "task.failed" => "task_failed",
      "task.paused" => "task_paused",
      "task.resumed" => "task_resumed",

      # Project events
      "project.created" => "project_created",
      "project.activated" => "project_activated",
      "project.completed" => "project_completed",
      "project.paused" => "project_paused",
      "project.resumed" => "project_resumed",

      # Agent events
      "agent.started" => "agent_started",
      "agent.completed" => "agent_completed",
      "agent.failed" => "agent_failed",

      # Research events
      "code_research.task" => "code_research_task",
      "code_research.discovery" => "code_discovery",
      "research.findings" => "research_findings",

      # Human interaction events
      "human_input.requested" => "human_input_requested",
      "human_input.provided" => "human_input_provided",
      "human_input.processed" => "human_input_processed"

      # Default case: return the original event type if no mapping exists
    }

    mapping[new_event_type] || new_event_type
  end
end
