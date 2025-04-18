# frozen_string_literal: true

# EventMigrationExample: Example service showing how to migrate from legacy Event.publish to EventService
# This serves as a guide for refactoring existing code to use the new event system
class EventMigrationExample
  class << self
    # Old way of publishing events
    def old_publish_tool_execution(tool_name, args, agent_activity)
      Event.publish(
        "tool_execution_started",
        {
          tool: tool_name,
          args: args
        },
        {
          agent_activity_id: agent_activity.id,
          task_id: agent_activity.task_id
        }
      )
    end

    # New way of publishing events
    def new_publish_tool_execution(tool_name, args, agent_activity)
      EventService.publish(
        "tool_execution.started",
        {
          tool: tool_name,
          args: args
        },
        {
          agent_activity_id: agent_activity.id,
          task_id: agent_activity.task_id
        }
      )
    end

    # Old way of publishing agent events
    def old_publish_agent_started(agent_type, agent_id, purpose, agent_activity)
      Event.publish(
        "agent_started",
        {
          agent_type: agent_type,
          agent_id: agent_id,
          purpose: purpose
        },
        {
          agent_activity_id: agent_activity.id,
          task_id: agent_activity.task_id
        }
      )
    end

    # New way of publishing agent events
    def new_publish_agent_started(agent_type, agent_id, purpose, agent_activity)
      EventService.publish(
        "agent.started",
        {
          agent_type: agent_type,
          agent_id: agent_id,
          purpose: purpose
        },
        {
          agent_activity_id: agent_activity.id,
          task_id: agent_activity.task_id
        }
      )
    end

    # Old way of publishing system events
    def old_publish_system_error(error_type, message, component)
      Event.publish(
        "system_error",
        {
          error_type: error_type,
          message: message,
          component: component
        },
        {
          system_event: true
        }
      )
    end

    # New way of publishing system events
    def new_publish_system_error(error_type, message, component)
      EventService.publish(
        "system.error",
        {
          error_type: error_type,
          message: message,
          component: component
        },
        {}
      )
    end

    # Migration guide for different event types
    def migration_examples
      {
        # Tool execution events
        "tool_execution_started" => "tool_execution.started",
        "tool_execution_finished" => "tool_execution.finished",
        "tool_execution_error" => "tool_execution.error",
        
        # Agent lifecycle events
        "agent_started" => "agent.started",
        "agent_completed" => "agent.completed",
        "agent_paused" => "agent.paused",
        "agent_resumed" => "agent.resumed",
        "agent_requested_human" => "agent.requested_human",
        
        # System events
        "system_startup" => "system.startup",
        "system_shutdown" => "system.shutdown",
        "system_error" => "system.error",
        "system_config_changed" => "system.config_changed",
        
        # Task events
        "subtask_completed" => "subtask.completed",
        "subtask_failed" => "subtask.failed",
        "task_waiting_on_human" => "task.waiting_on_human",
        "task_resumed" => "task.resumed",
        
        # Project events
        "project_created" => "project.created",
        "project_activated" => "project.activated",
        "project_stalled" => "project.stalled",
        "project_recoordination_requested" => "project.recoordination_requested",
        "project_paused" => "project.paused",
        "project_resumed" => "project.resumed",
        
        # Human input events
        "human_input_requested" => "human_input.requested",
        "human_input_provided" => "human_input.provided"
      }
    end

    # Helper method to determine the new event type from an old one
    def map_legacy_to_new_event_type(legacy_event_type)
      migration_examples[legacy_event_type] || legacy_event_type
    end
  end
end
