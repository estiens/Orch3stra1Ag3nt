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
    
    EventSchemaRegistry.register_schema(
      "system_resources_critical",
      { required: ["resource_type", "current_usage"], optional: ["threshold", "details"] },
      description: "System resources have reached a critical level"
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
    
    # Additional Agent Events
    EventSchemaRegistry.register_schema(
      "agent_completed",
      { required: ["agent_id", "agent_type", "result"], optional: ["duration", "metrics"] },
      description: "Agent completed its task"
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
    
    # Additional Task Events
    EventSchemaRegistry.register_schema(
      "task_created",
      { required: ["task_id", "title"], optional: ["description", "priority"] },
      description: "Task created (legacy format)"
    )
    
    EventSchemaRegistry.register_schema(
      "task_stuck",
      { required: ["task_id", "reason"], optional: ["duration", "details"] },
      description: "Task is stuck and needs intervention"
    )
    
    EventSchemaRegistry.register_schema(
      "task_waiting_on_human",
      { required: ["task_id", "prompt"], optional: ["timeout", "options"] },
      description: "Task is waiting for human input"
    )
    
    # Subtask Events
    EventSchemaRegistry.register_schema(
      "subtask_completed",
      { required: ["subtask_id", "task_id", "result"], optional: ["metrics"] },
      description: "Subtask completed successfully"
    )
    
    EventSchemaRegistry.register_schema(
      "subtask_failed",
      { required: ["subtask_id", "task_id", "error"], optional: ["stack_trace"] },
      description: "Subtask failed with error"
    )
    
    # Research Task Events
    EventSchemaRegistry.register_schema(
      "research_task_created",
      { required: ["task_id", "research_topic"], optional: ["scope", "depth"] },
      description: "Research task created"
    )
    
    EventSchemaRegistry.register_schema(
      "research_subtask_completed",
      { required: ["subtask_id", "task_id", "findings"], optional: ["sources"] },
      description: "Research subtask completed with findings"
    )
    
    EventSchemaRegistry.register_schema(
      "research_subtask_failed",
      { required: ["subtask_id", "task_id", "error"], optional: ["partial_findings"] },
      description: "Research subtask failed"
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
    
    # Helper method to register a handler for multiple event types
    def register_for_events(handler_class, events, description: nil, priority: 10)
      return unless defined?(handler_class)
      
      events.each do |event_type|
        EventBus.register_handler(
          event_type, 
          handler_class, 
          description: description || "Handles #{event_type} events",
          priority: priority
        )
      end
    end
    
    # -------------------------------------------------------------------------
    # Dashboard Event Handler - for real-time updates
    # -------------------------------------------------------------------------
    if defined?(DashboardEventHandler)
      # Task events
      register_for_events(
        DashboardEventHandler,
        [
          "task.activated", 
          "task.paused", 
          "task.resumed", 
          "task.completed", 
          "task.failed"
        ],
        description: "Updates dashboard with task status changes"
      )
      
      # Project events
      register_for_events(
        DashboardEventHandler,
        [
          "project.activated", 
          "project.paused", 
          "project.resumed", 
          "project.completed"
        ],
        description: "Updates dashboard with project status changes"
      )
      
      # Human input events
      register_for_events(
        DashboardEventHandler,
        [
          "human_input.requested", 
          "human_input.provided", 
          "human_input.ignored"
        ],
        description: "Updates dashboard with human input requests"
      )
      
      # Agent activity events
      register_for_events(
        DashboardEventHandler,
        [
          "agent_activity.created", 
          "agent_activity.completed", 
          "agent_activity.failed"
        ],
        description: "Updates dashboard with agent activities"
      )
      
      # LLM call events
      register_for_events(
        DashboardEventHandler,
        ["llm_call.completed"],
        description: "Updates dashboard with LLM call statistics"
      )
    end
    
    # -------------------------------------------------------------------------
    # Tool Execution Logger
    # -------------------------------------------------------------------------
    if defined?(ToolExecutionLogger)
      register_for_events(
        ToolExecutionLogger,
        [
          "tool_execution.started",
          "tool_execution.finished",
          "tool_execution.error"
        ],
        description: "Logs tool execution events",
        priority: 90 # High priority for logging
      )
    end
    
    # -------------------------------------------------------------------------
    # Orchestrator Agent - responds to various system events
    # -------------------------------------------------------------------------
    if defined?(OrchestratorAgent)
      # Explicit registration of OrchestratorAgent event handlers
      EventBus.register_handler("task_created", OrchestratorAgent, 
                               description: "Handle new tasks", 
                               priority: 20)
      EventBus.register_handler("task_stuck", OrchestratorAgent, 
                               description: "Handle stuck tasks", 
                               priority: 30)
      EventBus.register_handler("system_resources_critical", OrchestratorAgent, 
                               description: "Handle resource critical situations", 
                               priority: 50)
      EventBus.register_handler("project_created", OrchestratorAgent, 
                               description: "Handle new projects", 
                               priority: 20)
      EventBus.register_handler("project_activated", OrchestratorAgent, 
                               description: "Handle project activation", 
                               priority: 20)
      EventBus.register_handler("project_stalled", OrchestratorAgent, 
                               description: "Handle stalled projects", 
                               priority: 30)
      EventBus.register_handler("project_recoordination_requested", OrchestratorAgent, 
                               description: "Handle project recoordination requests", 
                               priority: 30)
      EventBus.register_handler("project_paused", OrchestratorAgent, 
                               description: "Handle paused projects", 
                               priority: 20)
      EventBus.register_handler("project_resumed", OrchestratorAgent, 
                               description: "Handle resumed projects", 
                               priority: 20)
    end
    
    # -------------------------------------------------------------------------
    # Coordinator Agent - handles task coordination
    # -------------------------------------------------------------------------
    if defined?(CoordinatorAgent)
      # Explicit registration of CoordinatorAgent event handlers
      EventBus.register_handler("subtask_completed", CoordinatorAgent, 
                               description: "Handle completed subtasks", 
                               priority: 20)
      EventBus.register_handler("subtask_failed", CoordinatorAgent, 
                               description: "Handle failed subtasks", 
                               priority: 30)
      EventBus.register_handler("task_waiting_on_human", CoordinatorAgent, 
                               description: "Handle tasks waiting for human input", 
                               priority: 20)
      EventBus.register_handler("tool_execution_finished", CoordinatorAgent, 
                               description: "Handle tool execution completion", 
                               priority: 20)
      EventBus.register_handler("agent_completed", CoordinatorAgent, 
                               description: "Handle agent completion", 
                               priority: 20)
      EventBus.register_handler("human_input_provided", CoordinatorAgent, 
                               description: "Handle human input provision", 
                               priority: 20)
    end
    
    # -------------------------------------------------------------------------
    # Research Coordinator Agent - handles research tasks
    # -------------------------------------------------------------------------
    if defined?(ResearchCoordinatorAgent)
      # Explicit registration of ResearchCoordinatorAgent event handlers
      EventBus.register_handler("research_task_created", ResearchCoordinatorAgent, 
                               description: "Handle new research tasks", 
                               priority: 20)
      EventBus.register_handler("research_subtask_completed", ResearchCoordinatorAgent, 
                               description: "Handle completed research subtasks", 
                               priority: 20)
      EventBus.register_handler("research_subtask_failed", ResearchCoordinatorAgent, 
                               description: "Handle failed research subtasks", 
                               priority: 30)
    end
    
    # -------------------------------------------------------------------------
    # EventSubscriber classes - automatically register remaining subscribers
    # -------------------------------------------------------------------------
    
    # Find all classes that include EventSubscriber and register their subscriptions
    Rails.application.eager_load! if Rails.env.development?
    
    # Get all classes that include EventSubscriber
    event_subscriber_classes = ApplicationRecord.descendants.select do |klass|
      klass.included_modules.include?(EventSubscriber)
    end
    
    # Also check non-ActiveRecord classes if possible
    if defined?(Rails::Engine)
      ObjectSpace.each_object(Class).select do |klass|
        klass.included_modules.include?(EventSubscriber) if klass.respond_to?(:included_modules)
      end.each do |klass|
        event_subscriber_classes << klass unless event_subscriber_classes.include?(klass)
      end
    end
    
    # Register all event subscriptions from these classes
    # Skip the ones we've already explicitly registered
    explicitly_registered = {
      "OrchestratorAgent" => [
        "task_created", "task_stuck", "system_resources_critical", 
        "project_created", "project_activated", "project_stalled", 
        "project_recoordination_requested", "project_paused", "project_resumed"
      ],
      "CoordinatorAgent" => [
        "subtask_completed", "subtask_failed", "task_waiting_on_human",
        "tool_execution_finished", "agent_completed", "human_input_provided"
      ],
      "ResearchCoordinatorAgent" => [
        "research_task_created", "research_subtask_completed", "research_subtask_failed"
      ]
    }
    
    event_subscriber_classes.each do |subscriber_class|
      if subscriber_class.respond_to?(:event_subscriptions)
        class_name = subscriber_class.name
        
        subscriber_class.event_subscriptions.each do |event_type, callback|
          # Skip if we've already explicitly registered this handler
          next if explicitly_registered[class_name]&.include?(event_type.to_s)
          
          EventBus.register_handler(
            event_type,
            subscriber_class,
            description: "Auto-registered from #{class_name}"
          )
          Rails.logger.debug("Auto-registered #{class_name} for event: #{event_type}")
        end
      end
    end
    
    # Log the number of registered schemas and handlers
    Rails.logger.info("Event Registry initialized with #{EventSchemaRegistry.registered_schemas.size} schemas")
    Rails.logger.info("Event Registry initialized with #{EventBus.handler_registry.values.flatten.size} handler registrations")
  end
end
