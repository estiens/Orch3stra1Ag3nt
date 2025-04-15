# frozen_string_literal: true

# Event Registry Initializer
# Centralizes all event schema and subscriber registrations in one place
Rails.application.config.after_initialize do
  # Only run in server/console environments, not during asset precompilation
  if defined?(Rails::Server) || Rails.const_defined?('Console')
    Rails.logger.info("Initializing Event Registry...")
    
    # =========================================================================
    # REGISTER EVENT SCHEMAS
    # =========================================================================
    
    # System Events
    EventSchemaRegistry.register_schema(
      "system.startup",
      { required: ["version", "environment"], optional: ["config"] },
      description: "System startup event with version and environment information"
    )
    
    EventSchemaRegistry.register_schema(
      "system.shutdown",
      { required: ["reason"], optional: ["exit_code"] },
      description: "System shutdown event with reason"
    )
    
    # Agent Events
    EventSchemaRegistry.register_schema(
      "agent_activity.created",
      { required: ["agent_type", "purpose"], optional: ["options"] },
      description: "Agent activity created"
    )
    
    EventSchemaRegistry.register_schema(
      "agent_activity.completed",
      { required: ["result"], optional: ["duration", "metrics"] },
      description: "Agent activity completed successfully"
    )
    
    EventSchemaRegistry.register_schema(
      "agent_activity.failed",
      { required: ["error"], optional: ["stack_trace", "duration"] },
      description: "Agent activity failed with error"
    )
    
    # Task Events
    EventSchemaRegistry.register_schema(
      "task.created",
      { required: ["title", "description"], optional: ["dependencies", "priority"] },
      description: "Task created"
    )
    
    EventSchemaRegistry.register_schema(
      "task.activated",
      { required: ["task_id"], optional: ["activated_by"] },
      description: "Task activated and ready for processing"
    )
    
    EventSchemaRegistry.register_schema(
      "task.paused",
      { required: ["task_id"], optional: ["paused_by", "reason"] },
      description: "Task paused"
    )
    
    EventSchemaRegistry.register_schema(
      "task.resumed",
      { required: ["task_id"], optional: ["resumed_by"] },
      description: "Task resumed after being paused"
    )
    
    EventSchemaRegistry.register_schema(
      "task.completed",
      { required: ["task_id"], optional: ["result", "duration"] },
      description: "Task completed successfully"
    )
    
    EventSchemaRegistry.register_schema(
      "task.failed",
      { required: ["task_id", "error"], optional: ["stack_trace"] },
      description: "Task failed with error"
    )
    
    # Project Events
    EventSchemaRegistry.register_schema(
      "project.created",
      { required: ["title", "description"], optional: ["metadata"] },
      description: "Project created"
    )
    
    EventSchemaRegistry.register_schema(
      "project.activated",
      { required: ["project_id"], optional: ["activated_by"] },
      description: "Project activated"
    )
    
    EventSchemaRegistry.register_schema(
      "project.paused",
      { required: ["project_id"], optional: ["paused_by", "reason"] },
      description: "Project paused"
    )
    
    EventSchemaRegistry.register_schema(
      "project.resumed",
      { required: ["project_id"], optional: ["resumed_by"] },
      description: "Project resumed after being paused"
    )
    
    EventSchemaRegistry.register_schema(
      "project.completed",
      { required: ["project_id"], optional: ["summary", "metrics"] },
      description: "Project completed"
    )
    
    # Tool Events
    EventSchemaRegistry.register_schema(
      "tool_execution.started",
      { required: ["tool_name", "args"], optional: ["context"] },
      description: "Tool execution started"
    )
    
    EventSchemaRegistry.register_schema(
      "tool_execution.finished",
      { required: ["tool_name", "result"], optional: ["duration", "metrics"] },
      description: "Tool execution finished successfully"
    )
    
    EventSchemaRegistry.register_schema(
      "tool_execution.error",
      { required: ["tool_name", "error"], optional: ["args", "stack_trace"] },
      description: "Tool execution failed with error"
    )
    
    # Human Interaction Events
    EventSchemaRegistry.register_schema(
      "human_input.requested",
      { required: ["prompt", "request_type"], optional: ["options", "timeout"] },
      description: "Human input requested"
    )
    
    EventSchemaRegistry.register_schema(
      "human_input.provided",
      { required: ["input", "request_id"], optional: ["metadata"] },
      description: "Human input provided"
    )
    
    EventSchemaRegistry.register_schema(
      "human_input.ignored",
      { required: ["request_id"], optional: ["reason"] },
      description: "Human input request ignored or timed out"
    )
    
    # LLM Events
    EventSchemaRegistry.register_schema(
      "llm_call.started",
      { required: ["model", "prompt"], optional: ["options"] },
      description: "LLM call started"
    )
    
    EventSchemaRegistry.register_schema(
      "llm_call.completed",
      { 
        required: ["model", "response"], 
        optional: ["tokens", "duration", "prompt_tokens", "completion_tokens"] 
      },
      description: "LLM call completed successfully"
    )
    
    EventSchemaRegistry.register_schema(
      "llm_call.failed",
      { required: ["model", "error"], optional: ["prompt", "stack_trace"] },
      description: "LLM call failed with error"
    )
    
    # =========================================================================
    # REGISTER EVENT SUBSCRIBERS
    # =========================================================================
    
    # Dashboard Event Handler - for real-time updates
    if defined?(DashboardEventHandler)
      EventBus.register_handler("task.activated", DashboardEventHandler, 
                               description: "Updates dashboard with task status changes")
      EventBus.register_handler("task.paused", DashboardEventHandler)
      EventBus.register_handler("task.resumed", DashboardEventHandler)
      EventBus.register_handler("task.completed", DashboardEventHandler)
      EventBus.register_handler("task.failed", DashboardEventHandler)
      
      EventBus.register_handler("project.activated", DashboardEventHandler,
                               description: "Updates dashboard with project status changes")
      EventBus.register_handler("project.paused", DashboardEventHandler)
      EventBus.register_handler("project.resumed", DashboardEventHandler)
      EventBus.register_handler("project.completed", DashboardEventHandler)
      
      EventBus.register_handler("human_input.requested", DashboardEventHandler,
                               description: "Updates dashboard with human input requests")
      EventBus.register_handler("human_input.provided", DashboardEventHandler)
      EventBus.register_handler("human_input.ignored", DashboardEventHandler)
      
      EventBus.register_handler("agent_activity.created", DashboardEventHandler,
                               description: "Updates dashboard with agent activities")
      EventBus.register_handler("agent_activity.completed", DashboardEventHandler)
      EventBus.register_handler("agent_activity.failed", DashboardEventHandler)
      
      EventBus.register_handler("llm_call.completed", DashboardEventHandler,
                               description: "Updates dashboard with LLM call statistics")
    end
    
    # Tool Execution Logger
    if defined?(ToolExecutionLogger)
      EventBus.register_handler("tool_execution.started", ToolExecutionLogger,
                               description: "Logs tool execution start")
      EventBus.register_handler("tool_execution.finished", ToolExecutionLogger,
                               description: "Logs tool execution completion")
      EventBus.register_handler("tool_execution.error", ToolExecutionLogger,
                               description: "Logs tool execution errors")
    end
    
    # Orchestrator Agent - responds to various system events
    if defined?(OrchestratorAgent)
      EventBus.register_handler("task.created", OrchestratorAgent,
                               description: "Orchestrates task processing")
      EventBus.register_handler("task.completed", OrchestratorAgent,
                               description: "Updates task dependencies when tasks complete")
      EventBus.register_handler("project.created", OrchestratorAgent,
                               description: "Initializes project processing")
    end
    
    # Log the number of registered schemas and handlers
    Rails.logger.info("Event Registry initialized with #{EventSchemaRegistry.registered_schemas.size} schemas")
    Rails.logger.info("Event Registry initialized with #{EventBus.handler_registry.values.flatten.size} handler registrations")
  end
end
