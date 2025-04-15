# Register event handlers with the EventBus
Rails.application.config.after_initialize do
  # Register the dashboard event handler for various event types
  dashboard_handler = DashboardEventHandler.new
  
  # Task events
  EventBus.register_handler('task_activated', dashboard_handler)
  EventBus.register_handler('task_paused', dashboard_handler)
  EventBus.register_handler('task_resumed', dashboard_handler)
  EventBus.register_handler('task_completed', dashboard_handler)
  EventBus.register_handler('task_failed', dashboard_handler)
  
  # Project events
  EventBus.register_handler('project_activated', dashboard_handler)
  EventBus.register_handler('project_paused', dashboard_handler)
  EventBus.register_handler('project_resumed', dashboard_handler)
  EventBus.register_handler('project_completed', dashboard_handler)
  
  # Human input events
  EventBus.register_handler('human_input_requested', dashboard_handler)
  EventBus.register_handler('human_input_provided', dashboard_handler)
  EventBus.register_handler('human_input_ignored', dashboard_handler)
  
  # Agent activity events
  EventBus.register_handler('agent_activity_created', dashboard_handler)
  EventBus.register_handler('agent_activity_completed', dashboard_handler)
  EventBus.register_handler('agent_activity_failed', dashboard_handler)
  
  # LLM call events
  EventBus.register_handler('llm_call_completed', dashboard_handler)
  
  Rails.logger.info "Registered DashboardEventHandler with EventBus"
end
