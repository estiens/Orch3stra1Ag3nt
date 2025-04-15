class ToolExecutionLogger
  # Central handler method called by EventBus
  def handle_event(event)
    # Ensure the event has the necessary data structure
    payload = event.data.is_a?(Hash) ? event.data : {}
    # Add agent_activity_id for context, assuming it's available on the Event model
    payload[:agent_activity_id] = event.agent_activity_id if event.respond_to?(:agent_activity_id)

    case event.event_type.to_s
    when "tool_execution_started"
      log_tool_started(payload)
    when "tool_execution_finished"
      log_tool_finished(payload)
    when "tool_execution_error"
      log_tool_error(payload)
    else
      # Optionally log unexpected event types if needed
      # Rails.logger.debug "[ToolExecutionLogger] Received unhandled event type: #{event.event_type}"
    end
  end

  private

  def log_tool_started(payload)
    tool_name = payload.dig(:tool) || "unknown_tool"
    args = payload.dig(:args) || "no_args"
    activity_id = payload[:agent_activity_id]
    Rails.logger.info "[Tool Event] Started: #{tool_name}(#{args}) [Activity: #{activity_id}]"
  end

  def log_tool_finished(payload)
    tool_name = payload.dig(:tool) || "unknown_tool"
    result_preview = payload.dig(:result_preview) || "no_result"
    activity_id = payload[:agent_activity_id]
    Rails.logger.info "[Tool Event] Finished: #{tool_name} -> #{result_preview} [Activity: #{activity_id}]"
  end

  def log_tool_error(payload)
    tool_name = payload.dig(:tool) || "unknown_tool"
    error_message = payload.dig(:error) || "unknown_error"
    activity_id = payload[:agent_activity_id]
    Rails.logger.error "[Tool Event] Error: #{tool_name} -> #{error_message} [Activity: #{activity_id}]"
  end
end
