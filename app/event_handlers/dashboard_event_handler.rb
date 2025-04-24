class DashboardEventHandler
  include BaseHandler

  # Handler method called by RailsEventStore (new approach)
  def call(event)
    event_type = event.event_type

    # Convert dot notation to legacy format for backward compatibility
    legacy_event_type = event_type.to_s.gsub(".", "_")

    # Process different event types
    process_event_type(legacy_event_type)

    # Log the event for debugging
    Rails.logger.info "DashboardEventHandler processed event: #{event_type}"
  end

  private

  def process_event_type(event_type)
    case event_type
    when "task_activated", "task_paused", "task_resumed", "task_completed", "task_failed",
         "task.activated", "task.paused", "task.resumed", "task.completed", "task.failed"
      broadcast_tasks_update
    when "project_activated", "project_paused", "project_resumed", "project_completed",
         "project.activated", "project.paused", "project.resumed", "project.completed"
      broadcast_projects_update
    when "human_input_requested", "human_input_provided", "human_input_ignored",
         "human_input.requested", "human_input.provided", "human_input.ignored"
      broadcast_human_input_requests_update
    when "agent_activity_created", "agent_activity_completed", "agent_activity_failed",
         "agent_activity.created", "agent_activity.completed", "agent_activity.failed"
      broadcast_agent_activities_update
    when "llm_call_completed", "llm_call.completed"
      broadcast_llm_calls_update
    end
  end

  def broadcast_tasks_update
    Turbo::StreamsChannel.broadcast_replace_to(
      "dashboard",
      target: "tasks-container",
      partial: "dashboard/tasks",
      locals: { tasks: Task.where(state: [ "active", "pending", "waiting_on_human", "paused" ]).order(created_at: :desc).limit(10) }
    )
  end

  def broadcast_projects_update
    Turbo::StreamsChannel.broadcast_replace_to(
      "dashboard",
      target: "projects-container",
      partial: "dashboard/projects",
      locals: { projects: Project.order(created_at: :desc).limit(10) }
    )
  end

  def broadcast_human_input_requests_update
    Turbo::StreamsChannel.broadcast_replace_to(
      "dashboard",
      target: "human-input-requests-container",
      partial: "dashboard/human_input_requests",
      locals: { human_input_requests: HumanInteraction.input_requests.pending.order(created_at: :desc).limit(10) }
    )
  end

  def broadcast_agent_activities_update
    Turbo::StreamsChannel.broadcast_replace_to(
      "dashboard",
      target: "agent-activities-container",
      partial: "dashboard/agent_activities",
      locals: { agent_activities: AgentActivity.order(created_at: :desc).limit(20) }
    )
  end

  def broadcast_llm_calls_update
    Turbo::StreamsChannel.broadcast_replace_to(
      "dashboard",
      target: "llm-calls-container",
      partial: "dashboard/llm_calls",
      locals: { llm_calls: LlmCall.order(created_at: :desc).limit(15) }
    )
  end
end
