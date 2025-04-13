# OrchestratorAgent: High-level task orchestration and management
# This agent is short-lived and spawned by events or recurring jobs
class OrchestratorAgent < BaseAgent
  include EventSubscriber

  # Define a highest-priority queue
  def self.queue_name
    :orchestrator
  end

  # Limit concurrency to 1 orchestrator at a time
  # This prevents conflicting decisions about system-wide orchestration
  def self.concurrency_limit
    1
  end

  # Subscribe to relevant system events
  subscribe_to "task_created", :handle_new_task
  subscribe_to "task_stuck", :handle_stuck_task
  subscribe_to "system_resources_critical", :handle_resource_critical
  subscribe_to "project_created", :handle_new_project

  # Tools that the orchestrator can use
  tool :analyze_system_state, "Analyze the current system state"
  tool :spawn_coordinator, "Spawn a CoordinatorAgent for a specific task"
  tool :escalate_to_human, "Escalate an issue to human operators"
  tool :adjust_system_priorities, "Adjust priority of pending tasks"
  tool :check_resource_usage, "Check current system resource usage"

  # Schedule this agent to run periodically to check overall system state
  def self.configure_recurring_checks(interval = "every 10 minutes")
    configure_recurring(
      key: "system_health_check",
      schedule: interval,
      prompt: "Perform system health check and resource allocation",
      options: { purpose: "System health monitoring and resource allocation" }
    )
  end

  # Event handler for new task events
  def handle_new_task(event)
    task_id = event.data["task_id"]
    return if task_id.blank?

    task = Task.find(task_id)

    run("Analyze newly created task and determine appropriate agent allocation:\n" +
        "Task ID: #{task.id}\n" +
        "Title: #{task.title}\n" +
        "Description: #{task.description}\n" +
        "Priority: #{task.priority}")
  end

  # Event handler for stuck tasks
  def handle_stuck_task(event)
    task_id = event.data["task_id"]
    return if task_id.blank?

    task = Task.find(task_id)
    stuck_duration = event.data["stuck_duration"] || "unknown"

    run("Analyze stuck task and determine remediation actions:\n" +
        "Task ID: #{task.id}\n" +
        "Title: #{task.title}\n" +
        "Description: #{task.description}\n" +
        "Status: #{task.state}\n" +
        "Stuck for: #{stuck_duration}")
  end

  # Event handler for critical resource situations
  def handle_resource_critical(event)
    resource_type = event.data["resource_type"]
    usage_percent = event.data["usage_percent"]

    run("Handle critical resource situation:\n" +
        "Resource: #{resource_type}\n" +
        "Usage: #{usage_percent}%\n" +
        "Take immediate action to prevent system degradation.")
  end

  # Event handler for new project events
  def handle_new_project(event)
    project_id = event.data["project_id"]
    task_id = event.data["task_id"]
    return if project_id.blank? || task_id.blank?

    project = Project.find(project_id)
    task = Task.find(task_id)

    run("Analyze newly created project and create initial project plan:\n" +
        "Project: #{project.name}\n" +
        "Description: #{project.description}\n" +
        "Priority: #{project.priority}\n" +
        "Settings: #{project.settings.to_json}\n" +
        "Create a comprehensive project plan with appropriate tasks and research needs.")
  end

  # Tool implementation: Analyze current system state
  def analyze_system_state(query = nil)
    # Get active tasks
    active_tasks = Task.active.count
    waiting_tasks = Task.where(state: :waiting_on_human).count
    completed_tasks = Task.where(state: :completed).count
    failed_tasks = Task.where(state: :failed).count

    # Get agent stats
    active_agents = AgentActivity.where(status: "running").count

    # Check queue depths
    total_queued_jobs = SolidQueue::Job.where(finished_at: nil).count

    # Queue stats by type
    queue_stats = {}
    SolidQueue::Job.where(finished_at: nil).group(:queue_name).count.each do |queue, count|
      queue_stats[queue] = count
    end

    # Get recent errors
    recent_errors = Event.where(event_type: "agent_error").recent.limit(5)
    error_summary = recent_errors.map { |e| "#{e.data['error_type']}: #{e.data['error_message']&.truncate(50)}" }.join("\n")

    # Prepare system status for LLM analysis
    system_data = {
      tasks: {
        active: active_tasks,
        waiting_on_human: waiting_tasks,
        completed: completed_tasks,
        failed: failed_tasks
      },
      agents: {
        active: active_agents
      },
      queues: {
        total_pending: total_queued_jobs,
        by_queue: queue_stats
      },
      errors: {
        recent: error_summary
      }
    }

    # Create prompt for LLM analysis
    prompt = <<~PROMPT
      As the OrchestratorAgent, analyze the current system state and recommend actions:

      CURRENT SYSTEM METRICS:
      #{JSON.pretty_generate(system_data)}

      #{query.present? ? "SPECIFIC QUERY: #{query}\n\n" : ""}
      Based on these metrics, please provide:
      1. A concise assessment of the current system state
      2. Key areas that need attention (if any)
      3. Recommended actions to optimize system performance
      4. Resource allocation suggestions

      FORMAT AS:
      SYSTEM STATE: [assessment]

      KEY AREAS OF CONCERN:
      - [area 1]
      - [area 2]

      RECOMMENDED ACTIONS:
      - [action 1]
      - [action 2]

      RESOURCE ALLOCATION:
      - [suggestion 1]
      - [suggestion 2]
    PROMPT

    # Use the thinking model for complex analysis
    thinking_model = Regent::LLM.new(REGENT_MODEL_DEFAULTS[:thinking], temperature: 0.4)
    result = thinking_model.invoke(prompt)

    # Log this LLM call
    if agent_activity
      agent_activity.llm_calls.create!(
        provider: "openrouter",
        model: REGENT_MODEL_DEFAULTS[:thinking],
        prompt: prompt,
        response: result.content,
        tokens_used: (result.input_tokens || 0) + (result.output_tokens || 0)
      )
    end

    # Return the LLM's analysis
    result.content
  end

  # Tool implementation: Spawn a coordinator agent for a task
  def spawn_coordinator(task_id, priority = nil)
    task = Task.find(task_id)

    # Create options for the coordinator
    options = {
      task_id: task.id,
      parent_activity_id: agent_activity&.id,
      purpose: "Coordinate execution of task: #{task.title}"
    }

    # Add priority if specified
    options[:priority] = priority if priority.present?

    # Enqueue the coordinator agent
    CoordinatorAgent.enqueue("Coordinate task execution for: #{task.title}\n#{task.description}", options)

    # Create a record of this orchestration decision
    agent_activity&.events.create!(
      event_type: "coordinator_spawned",
      data: {
        task_id: task.id,
        priority: priority || "default"
      }
    )

    "Spawned CoordinatorAgent for task #{task_id} with #{priority || 'default'} priority"
  end

  # Tool implementation: Escalate an issue to human operators
  def escalate_to_human(issue_description, urgency = "normal")
    # Create a human intervention request
    intervention = HumanIntervention.create!(
      description: issue_description,
      urgency: urgency,
      status: "pending",
      agent_activity_id: agent_activity&.id
    )

    # Emit an event for dashboard notification
    Event.publish(
      "human_intervention_requested",
      {
        intervention_id: intervention.id,
        description: issue_description,
        urgency: urgency
      },
      priority: urgency == "critical" ? Event::CRITICAL_PRIORITY : Event::HIGH_PRIORITY
    )

    # For critical issues, could also send notifications via other channels
    # like email/Slack/SMS, etc.

    "Escalated to human operators with #{urgency} urgency. Intervention ID: #{intervention.id}"
  end

  # Tool implementation: Adjust system priorities
  def adjust_system_priorities(adjustments)
    results = []

    # Parse the adjustments string into structured data
    # Expected format: "task_id:priority_level, task_id:priority_level, ..."
    adjustment_pairs = adjustments.split(",").map(&:strip)

    adjustment_pairs.each do |pair|
      task_id, priority = pair.split(":").map(&:strip)

      begin
        task = Task.find(task_id)
        original_priority = task.priority

        # Update the task priority
        task.update!(priority: priority)

        # Record the change
        task.events.create!(
          event_type: "priority_adjusted",
          data: {
            from: original_priority,
            to: priority,
            adjusted_by: "OrchestratorAgent"
          }
        )

        results << "Task #{task_id}: priority changed from #{original_priority} to #{priority}"
      rescue => e
        results << "Failed to adjust task #{task_id}: #{e.message}"
      end
    end

    results.join("\n")
  end

  # Tool implementation: Check current resource usage
  def check_resource_usage
    # Get actual metrics instead of simulated ones

    # Check database connections
    db_connections = ActiveRecord::Base.connection_pool.connections.count
    db_pool_size = ActiveRecord::Base.connection_pool.size
    db_usage_percent = (db_connections.to_f / db_pool_size * 100).round(1)

    # Get queue stats
    queue_depths = {}
    queue_stats = SolidQueue::Job.where(finished_at: nil).group(:queue_name).count

    # Get system memory usage through system call - works on Linux/Mac
    begin
      memory_info = {}
      if RUBY_PLATFORM =~ /darwin/
        # macOS command
        memory = `vm_stat`
        free_blocks = memory.match(/Pages free:\s+(\d+)/)[1].to_i
        inactive_blocks = memory.match(/Pages inactive:\s+(\d+)/)[1].to_i
        total_blocks = free_blocks + inactive_blocks + memory.match(/Pages active:\s+(\d+)/)[1].to_i +
                      memory.match(/Pages wired down:\s+(\d+)/)[1].to_i
        memory_usage = ((total_blocks - free_blocks - inactive_blocks).to_f / total_blocks * 100).round(1)
        memory_info = { usage_percent: memory_usage }
      else
        # Linux command
        memory = `free -m`
        total = memory.match(/^Mem:\s+(\d+)/)[1].to_i
        used = memory.match(/^Mem:\s+\d+\s+(\d+)/)[1].to_i
        memory_usage = ((used.to_f / total) * 100).round(1)
        memory_info = { usage_percent: memory_usage, total_mb: total, used_mb: used }
      end
    rescue => e
      memory_info = { error: "Failed to get memory info: #{e.message}" }
      memory_usage = nil
    end

    # Get CPU usage - simplified approach
    begin
      if RUBY_PLATFORM =~ /darwin/
        # macOS top command for CPU usage
        cpu_info = `top -l 1 -n 0 | grep "CPU usage"`
        cpu_usage = cpu_info.match(/(\d+\.\d+)% user/)[1].to_f +
                   cpu_info.match(/(\d+\.\d+)% sys/)[1].to_f
      else
        # Linux CPU usage
        cpu_info = `top -bn1 | grep "Cpu(s)"`
        cpu_usage = 100 - cpu_info.match(/(\d+\.\d+)\s*id/)[1].to_f
      end
    rescue => e
      cpu_usage = nil
    end

    # Get API usage info (if available)
    # This would be coming from a real API rate limiting monitor
    # For now, we'll track LLM calls in the last 24 hours
    recent_llm_calls = LlmCall.where("created_at > ?", 24.hours.ago).count
    daily_limit = ENV["DAILY_LLM_CALL_LIMIT"].to_i
    daily_limit = 1000 if daily_limit == 0 # default if not set
    api_quota_used = (recent_llm_calls.to_f / daily_limit * 100).round(1)

    # Get queue depths from SolidQueue
    orchestrator_queue_depth = SolidQueue::Job.where(queue_name: "orchestrator", finished_at: nil).count
    coordinator_queue_depth = SolidQueue::Job.where(queue_name: "coordinator", finished_at: nil).count
    agent_queue_depth = SolidQueue::Job.where(queue_name: "agents", finished_at: nil).count

    # Format the resource data
    resource_data = {
      system: {
        cpu_usage: cpu_usage || "Unknown",
        memory_usage: memory_usage || "Unknown",
        db_connections: {
          current: db_connections,
          max: db_pool_size,
          usage_percent: db_usage_percent
        },
        api_quota: {
          calls_last_24h: recent_llm_calls,
          daily_limit: daily_limit,
          usage_percent: api_quota_used
        }
      },
      queues: {
        orchestrator: orchestrator_queue_depth,
        coordinator: coordinator_queue_depth,
        agents: agent_queue_depth,
        other: queue_stats.except("orchestrator", "coordinator", "agents")
      }
    }

    # Use LLM to analyze the resource usage
    prompt = <<~PROMPT
      As the OrchestratorAgent, analyze the current resource usage metrics:

      RESOURCE METRICS:
      #{JSON.pretty_generate(resource_data)}

      Based on these metrics, please provide:
      1. A concise assessment of resource health
      2. Any resource constraints or bottlenecks
      3. Specific recommendations for resource optimization

      FORMAT AS:
      RESOURCE HEALTH: [overall assessment]

      CONSTRAINTS:
      - [constraint 1]
      - [constraint 2]

      RECOMMENDATIONS:
      - [recommendation 1]
      - [recommendation 2]
    PROMPT

    # Use a fast model for this analysis
    fast_model = Regent::LLM.new(REGENT_MODEL_DEFAULTS[:fast], temperature: 0.2)
    result = fast_model.invoke(prompt)

    # Log this LLM call
    if agent_activity
      agent_activity.llm_calls.create!(
        provider: "openrouter",
        model: REGENT_MODEL_DEFAULTS[:fast],
        prompt: prompt,
        response: result.content,
        tokens_used: (result.input_tokens || 0) + (result.output_tokens || 0)
      )
    end

    # Return the LLM's analysis
    result.content
  end

  private

  # Special after_run for orchestrator to clean up
  def after_run
    super

    # For OrchestratorAgent, log decisions made
    decision_log = "OrchestratorAgent #{self.object_id} decisions:\n"

    session_trace&.tool_executions&.each do |tool_exec|
      case tool_exec[:tool]
      when "spawn_coordinator"
        decision_log += "- Spawned coordinator for task #{tool_exec[:args]['task_id']}\n"
      when "escalate_to_human"
        decision_log += "- Escalated issue to human: #{tool_exec[:args]['issue_description']}\n"
      when "adjust_system_priorities"
        decision_log += "- Adjusted priorities: #{tool_exec[:args]['adjustments']}\n"
      end
    end

    Rails.logger.info(decision_log)
  end
end
