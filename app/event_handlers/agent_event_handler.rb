# frozen_string_literal: true

# AgentEventHandler: Handles agent lifecycle events
# Logs agent starts, completions, pauses, resumes, and human interaction requests
class AgentEventHandler
  include BaseHandler

  def call(event)
    event_type = event.event_type
    payload = event.data

    case event_type
    when "agent.started"
      log_agent_started(payload, event.metadata)
    when "agent.completed"
      log_agent_completed(payload, event.metadata)
    when "agent.paused"
      log_agent_paused(payload, event.metadata)
    when "agent.resumed"
      log_agent_resumed(payload, event.metadata)
    when "agent.requested_human"
      log_agent_requested_human(payload, event.metadata)
    else
      log_handler_activity(event, "Received unhandled agent event type")
    end
  end

  private

  def log_agent_started(payload, metadata)
    agent_type = payload[:agent_type] || "unknown"
    agent_id = payload[:agent_id] || "unknown"
    purpose = payload[:purpose] || "no purpose specified"
    task_id = metadata[:task_id]
    activity_id = metadata[:agent_activity_id]

    Rails.logger.info "[Agent Event] Started: #{agent_type}(#{agent_id}) for '#{purpose}' [Task: #{task_id}, Activity: #{activity_id}]"
  end

  def log_agent_completed(payload, metadata)
    agent_type = payload[:agent_type] || "unknown"
    agent_id = payload[:agent_id] || "unknown"
    status = payload[:status] || "unknown"
    duration = payload[:duration_ms] ? "#{(payload[:duration_ms] / 1000.0).round(2)}s" : "unknown"
    task_id = metadata[:task_id]
    activity_id = metadata[:agent_activity_id]

    Rails.logger.info "[Agent Event] Completed: #{agent_type}(#{agent_id}) with status '#{status}' (duration: #{duration}) [Task: #{task_id}, Activity: #{activity_id}]"
  end

  def log_agent_paused(payload, metadata)
    agent_type = payload[:agent_type] || "unknown"
    agent_id = payload[:agent_id] || "unknown"
    reason = payload[:reason] || "unknown reason"
    initiated_by = payload[:initiated_by] || "system"
    task_id = metadata[:task_id]
    activity_id = metadata[:agent_activity_id]

    Rails.logger.info "[Agent Event] Paused: #{agent_type}(#{agent_id}) due to '#{reason}' initiated by #{initiated_by} [Task: #{task_id}, Activity: #{activity_id}]"
  end

  def log_agent_resumed(payload, metadata)
    agent_type = payload[:agent_type] || "unknown"
    agent_id = payload[:agent_id] || "unknown"
    pause_duration = payload[:pause_duration_ms] ? "#{(payload[:pause_duration_ms] / 1000.0).round(2)}s" : "unknown"
    initiated_by = payload[:initiated_by] || "system"
    task_id = metadata[:task_id]
    activity_id = metadata[:agent_activity_id]

    Rails.logger.info "[Agent Event] Resumed: #{agent_type}(#{agent_id}) after #{pause_duration} initiated by #{initiated_by} [Task: #{task_id}, Activity: #{activity_id}]"
  end

  def log_agent_requested_human(payload, metadata)
    agent_type = payload[:agent_type] || "unknown"
    agent_id = payload[:agent_id] || "unknown"
    request_type = payload[:request_type] || "unknown"
    prompt = payload[:prompt] || "no prompt"
    priority = payload[:priority] || "normal"
    task_id = metadata[:task_id]
    activity_id = metadata[:agent_activity_id]

    Rails.logger.info "[Agent Event] Human Requested: #{agent_type}(#{agent_id}) needs #{request_type} - '#{prompt.truncate(50)}' (priority: #{priority}) [Task: #{task_id}, Activity: #{activity_id}]"
  end
end
