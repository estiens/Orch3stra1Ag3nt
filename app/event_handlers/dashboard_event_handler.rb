class DashboardEventHandler
  # Central handler method called by EventBus
  def handle_event(event)
    # Process different event types
    case event.event_type.to_s
    when "task_activated", "task_paused", "task_resumed", "task_completed", "task_failed"
      broadcast_tasks_update
    when "project_activated", "project_paused", "project_resumed", "project_completed"
      broadcast_projects_update
    when "human_input_requested", "human_input_provided", "human_input_ignored"
      broadcast_human_input_requests_update
    when "agent_activity_created", "agent_activity_completed", "agent_activity_failed"
      broadcast_agent_activities_update
    when "llm_call_completed"
      broadcast_llm_calls_update
    end

    # Log the event for debugging
    Rails.logger.info "DashboardEventHandler processed event: #{event.event_type}"
  end

  private

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
      locals: { human_input_requests: HumanInputRequest.where(status: "pending").order(created_at: :desc).limit(10) }
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
