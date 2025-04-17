# frozen_string_literal: true

# ToolExecutionHandler: Handles tool execution events
# Logs tool starts, completions, and errors
class ToolExecutionHandler
  include BaseHandler

  def call(event)
    event_type = event.event_type
    payload = event.data

    case event_type
    when "tool_execution.started"
      log_tool_started(payload, event.metadata)
    when "tool_execution.finished"
      log_tool_finished(payload, event.metadata)
    when "tool_execution.error"
      log_tool_error(payload, event.metadata)
    else
      log_handler_activity(event, "Received unhandled event type")
    end
  end

  private

  def log_tool_started(payload, metadata)
    tool_name = payload[:tool] || "unknown_tool"
    args = payload[:args] || "no_args"
    activity_id = metadata[:agent_activity_id]
    Rails.logger.info "[Tool Event] Started: #{tool_name}(#{args}) [Activity: #{activity_id}]"
  end

  def log_tool_finished(payload, metadata)
    tool_name = payload[:tool] || "unknown_tool"
    result_preview = payload[:result].to_s.truncate(100) || "no_result"
    activity_id = metadata[:agent_activity_id]
    Rails.logger.info "[Tool Event] Finished: #{tool_name} -> #{result_preview} [Activity: #{activity_id}]"
  end

  def log_tool_error(payload, metadata)
    tool_name = payload[:tool] || "unknown_tool"
    error_message = payload[:error] || "unknown_error"
    activity_id = metadata[:agent_activity_id]
    Rails.logger.error "[Tool Event] Error: #{tool_name} -> #{error_message} [Activity: #{activity_id}]"
  end
end