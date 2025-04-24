# frozen_string_literal: true

# SystemEventHandler: Handles system-related events
# Logs system startups, shutdowns, errors, and configuration changes
class SystemEventHandler
  include BaseHandler

  def call(event)
    event_type = event.event_type
    payload = event.data

    case event_type
    when "system.startup"
      log_system_startup(payload, event.metadata)
    when "system.shutdown"
      log_system_shutdown(payload, event.metadata)
    when "system.error"
      log_system_error(payload, event.metadata)
    when "system.config_changed"
      log_config_change(payload, event.metadata)
    else
      log_handler_activity(event, "Received unhandled system event type")
    end
  end

  private

  def log_system_startup(payload, metadata)
    version = payload[:version] || "unknown"
    environment = payload[:environment] || "unknown"
    boot_time = payload[:boot_time_ms] ? "#{payload[:boot_time_ms]}ms" : "unknown"
    correlation_id = metadata[:correlation_id]

    Rails.logger.info "[System Event] Startup: v#{version} in #{environment} environment (boot: #{boot_time}) [Correlation: #{correlation_id}]"
  end

  def log_system_shutdown(payload, metadata)
    reason = payload[:reason] || "unknown"
    exit_code = payload[:exit_code] || -1
    uptime = payload[:uptime_ms] ? "#{(payload[:uptime_ms] / 1000.0).round(2)}s" : "unknown"
    correlation_id = metadata[:correlation_id]

    Rails.logger.info "[System Event] Shutdown: #{reason} (code: #{exit_code}, uptime: #{uptime}) [Correlation: #{correlation_id}]"
  end

  def log_system_error(payload, metadata)
    error_type = payload[:error_type] || "unknown"
    message = payload[:message] || "no message"
    component = payload[:component] || "unknown"
    severity = payload[:severity] || "error"
    correlation_id = metadata[:correlation_id]

    Rails.logger.error "[System Event] Error in #{component}: #{error_type} - #{message} (severity: #{severity}) [Correlation: #{correlation_id}]"

    # Log backtrace if available
    if payload[:backtrace].present?
      Rails.logger.error "[System Event] Backtrace: #{payload[:backtrace].join("\n")}"
    end
  end

  def log_config_change(payload, metadata)
    component = payload[:component] || "unknown"
    changes = payload[:changes] || {}
    user = payload[:user_id] || "system"
    correlation_id = metadata[:correlation_id]

    change_summary = changes.map { |k, v| "#{k}: #{v}" }.join(", ")
    Rails.logger.info "[System Event] Config Changed for #{component} by #{user}: #{change_summary} [Correlation: #{correlation_id}]"
  end
end
