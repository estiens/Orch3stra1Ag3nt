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
  subscribe_to "project_activated", :handle_project_activated
  subscribe_to "project_stalled", :handle_project_stalled

  # --- Tools ---
  # Use the new BaseAgent tool definition DSL
  tool :analyze_system_state, "Analyze the current system state" do |query = nil|
    analyze_system_state(query)
  end

  tool :spawn_coordinator, "Spawn a CoordinatorAgent for a specific task" do |task_id, priority = nil|
    spawn_coordinator(task_id, priority)
  end

  tool :escalate_to_human, "Escalate an issue to human operators" do |issue_description, urgency = "normal"|
    escalate_to_human(issue_description, urgency)
  end

  tool :adjust_system_priorities, "Adjust priority of pending tasks" do |adjustments|
    adjust_system_priorities(adjustments)
  end

  tool :check_resource_usage, "Check current system resource usage" do
    check_resource_usage
  end
  
  tool :recoordinate_project, "Trigger re-coordination of a project to evaluate progress and next steps" do |project_id|
    recoordinate_project(project_id)
  end
  # --- End Tools ---

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

    # Note: The 'run' method is now different. We might need to rethink how event handlers
    # trigger agent execution or if they directly use tools/logic.
    # For now, let's log the intention. A full run might be needed.
    Rails.logger.info "[OrchestratorAgent] Received handle_new_task for Task #{task_id}. Should analyze and allocate."
    # Potential direct tool call if appropriate context is available:
    # analyze_system_state("New task arrived: #{task.title}")
    # Or trigger a full run:
    # self.run(input: { purpose_override: "Analyze new task #{task.id}" }) # Depends on run implementation
  end

  # Event handler for stuck tasks
  def handle_stuck_task(event)
    task_id = event.data["task_id"]
    return if task_id.blank?

    task = Task.find(task_id)
    stuck_duration = event.data["stuck_duration"] || "unknown"

    Rails.logger.info "[OrchestratorAgent] Received handle_stuck_task for Task #{task_id}."
    # Similar to handle_new_task, decide how to proceed.
    # Potentially trigger run:
    # self.run(input: { purpose_override: "Analyze stuck task #{task.id}" })
  end

  # Event handler for critical resource situations
  def handle_resource_critical(event)
    resource_type = event.data["resource_type"]
    usage_percent = event.data["usage_percent"]

    Rails.logger.warn "[OrchestratorAgent] Received handle_resource_critical for #{resource_type} at #{usage_percent}%."
    # Potentially trigger run:
    # self.run(input: { purpose_override: "Handle critical resource: #{resource_type}" })
    # Or directly call tools like escalate_to_human or adjust_system_priorities
    # escalate_to_human("Critical resource: #{resource_type} at #{usage_percent}%", "critical")
  end

  # Event handler for new project events
  def handle_new_project(event)
    project_id = event.data["project_id"]
    task_id = event.data["task_id"] # Assuming a related task is created
    return if project_id.blank? || task_id.blank?

    project = Project.find(project_id)
    task = Task.find(task_id) # Assuming this is the initial task

    Rails.logger.info "[OrchestratorAgent] Received handle_new_project for #{project.name}."
    # We'll let the project_activated event handle the actual kickoff
  end

  # Event handler for project activation (kickoff)
  def handle_project_activated(event)
    project_id = event.data["project_id"]
    return if project_id.blank?

    project = Project.find(project_id)

    # Find the root task for this project
    root_task = project.root_tasks.first
    return unless root_task

    Rails.logger.info "[OrchestratorAgent] Received handle_project_activated for #{project.name}. Spawning coordinator."

    # Spawn a coordinator agent to handle the root task
    coordinator_result = spawn_coordinator(root_task.id, "high")

    # Update task status
    root_task.update!(
      notes: "Task initiated by OrchestratorAgent in response to project activation."
    )

    # Activate the task if it's not already active
    if root_task.may_activate?
      root_task.activate!
      Rails.logger.info "[OrchestratorAgent] Activated root task #{root_task.id} for project #{project.name}"
    end

    # Log the action
    agent_activity&.events.create!(
      event_type: "coordinator_spawned_for_project",
      data: {
        project_id: project.id,
        project_name: project.name,
        task_id: root_task.id,
        coordinator_result: coordinator_result
      }
    )
  end
  
  # Event handler for stalled projects
  def handle_project_stalled(event)
    project_id = event.data["project_id"]
    return if project_id.blank?
    
    project = Project.find(project_id)
    reason = event.data["reason"] || "No progress detected"
    
    Rails.logger.warn "[OrchestratorAgent] Received handle_project_stalled for #{project.name}. Reason: #{reason}"
    
    # Trigger re-coordination for the stalled project
    recoordination_result = recoordinate_project(project_id)
    
    # Log the action
    agent_activity&.events.create!(
      event_type: "stalled_project_recoordination",
      data: { 
        project_id: project.id, 
        project_name: project.name,
        reason: reason,
        recoordination_result: recoordination_result
      }
    )
    
    # If the reason suggests a critical issue, also escalate to human
    if reason.include?("critical") || reason.include?("failed") || reason.include?("error")
      escalate_to_human(
        "STALLED PROJECT ALERT: #{project.name} (ID: #{project_id})\n\nReason: #{reason}\n\nAutomatic re-coordination has been initiated, but human review may be required.",
        "high"
      )
    end
  end

  # --- Core Logic ---
  # Override run to implement orchestrator logic
  def run(input = nil) # Input could be trigger info, but often unused for scheduled runs
    before_run(input)

    result_message = "Orchestrator run completed."
    begin
      Rails.logger.info "[OrchestratorAgent-#{agent_activity&.id}] Starting system analysis..."

      # Always analyze system state
      # Note: analyze_system_state calls the LLM internally
      system_analysis = execute_tool(:analyze_system_state, input)
      Rails.logger.info "[OrchestratorAgent-#{agent_activity&.id}] System Analysis Result:\n#{system_analysis}"

      # Check resource usage
      # Note: check_resource_usage calls the LLM internally
      resource_analysis = execute_tool(:check_resource_usage)
      Rails.logger.info "[OrchestratorAgent-#{agent_activity&.id}] Resource Usage Result:\n#{resource_analysis}"

      # TODO: Add logic based on the analysis results.
      # Example: If system analysis indicates high queue depth for :agents,
      # maybe adjust priorities? If resource analysis shows critical CPU,
      # escalate?
      #
      # Example Decision (placeholder):
      if system_analysis.include?("KEY AREAS OF CONCERN") || resource_analysis.include?("CONSTRAINTS")
         # Placeholder: Escalate if any concerns are found
         # In reality, parse the analysis more intelligently
         concern_summary = "System/Resource concerns detected. Analysis:\nSys: #{system_analysis.split("RECOMMENDED").first}\nRes: #{resource_analysis.split("RECOMMENDATIONS").first}".truncate(500)
         execute_tool(:escalate_to_human, concern_summary, "normal")
         result_message = "System/Resource analysis complete. Concerns found and escalated."
      else
         result_message = "System/Resource analysis complete. No major concerns detected."
      end

    rescue => e
      handle_run_error(e)
      raise # Re-raise after handling
    end

    @session_data[:output] = result_message
    after_run(result_message)
    result_message
  end
  # --- End Core Logic ---

  # --- Tool Implementations ---
  # (These are now called by the tool blocks above)

  # Tool implementation: Analyze current system state
  def analyze_system_state(query = nil)
    # ... (Gather metrics as before) ...
    active_tasks = Task.active.count
    waiting_tasks = Task.where(state: :waiting_on_human).count
    completed_tasks = Task.where(state: :completed).count
    failed_tasks = Task.where(state: :failed).count
    active_agents = AgentActivity.where(status: "running").count
    total_queued_jobs = SolidQueue::Job.where(finished_at: nil).count
    queue_stats = {}
    SolidQueue::Job.where(finished_at: nil).group(:queue_name).count.each do |queue, count|
      queue_stats[queue] = count
    end
    recent_errors = Event.where(event_type: "agent_error").recent.limit(5)
    error_summary = recent_errors.map { |e| "#{e.data['error_type']}: #{e.data['error_message']&.truncate(50)}" }.join("\n")

    system_data = {
      tasks: { active: active_tasks, waiting_on_human: waiting_tasks, completed: completed_tasks, failed: failed_tasks },
      agents: { active: active_agents },
      queues: { total_pending: total_queued_jobs, by_queue: queue_stats },
      errors: { recent: error_summary }
    }

    # Create prompt for LLM analysis using the agent's @llm
    prompt_content = <<~PROMPT
      Analyze the current system state and recommend actions based on the following metrics:

      CURRENT SYSTEM METRICS:
      #{JSON.pretty_generate(system_data)}

      #{query.present? ? "SPECIFIC QUERY: #{query}\n\n" : ""}
      Provide:
      1. Concise assessment of the current system state.
      2. Key areas needing attention.
      3. Recommended actions for optimization.
      4. Resource allocation suggestions.

      FORMAT AS:
      SYSTEM STATE: [assessment]

      KEY AREAS OF CONCERN:
      - [area 1]

      RECOMMENDED ACTIONS:
      - [action 1]

      RESOURCE ALLOCATION:
      - [suggestion 1]
    PROMPT

    # Use the agent's LLM instance (configured in BaseAgent)
    begin
      # Langchainrb typically uses .chat or .invoke depending on the chain/llm setup
      # Assuming .chat for direct LLM interaction:
      response = @llm.chat(messages: [ { role: "user", content: prompt_content } ])

      # Manually log the direct LLM call
      log_direct_llm_call(prompt_content, response)

      response.chat_completion # Or response.content depending on the LLM wrapper
    rescue => e
      Rails.logger.error "[OrchestratorAgent] Error during LLM call in analyze_system_state: #{e.message}"
      "Error analyzing system state: #{e.message}"
    end
  end

  # Tool implementation: Spawn a coordinator agent for a task
  def spawn_coordinator(task_id, priority = nil)
    task = Task.find(task_id)
    options = {
      task_id: task.id,
      parent_activity_id: agent_activity&.id,
      purpose: "Coordinate execution of task: #{task.title}"
    }
    options[:priority] = priority if priority.present?

    # Add project context if available
    if task.project_id
      options[:metadata] = {
        project_id: task.project_id,
        project_name: task.project.name
      }
    end

    CoordinatorAgent.enqueue("Coordinate task execution for: #{task.title}\n#{task.description}", options)

    agent_activity&.events.create!(
      event_type: "coordinator_spawned",
      data: {
        task_id: task.id,
        priority: priority || "default",
        project_id: task.project_id
      }
    )
    "Spawned CoordinatorAgent for task #{task_id} with #{priority || 'default'} priority"

  rescue ActiveRecord::RecordNotFound
    "Error: Task with ID #{task_id} not found."
  rescue => e
    Rails.logger.error "[OrchestratorAgent] Error spawning coordinator: #{e.message}"
    "Error spawning coordinator for task #{task_id}: #{e.message}"
  end

  # Tool implementation: Escalate an issue to human operators
  def escalate_to_human(issue_description, urgency = "normal")
    intervention = HumanIntervention.create!(
      description: issue_description,
      urgency: urgency,
      status: "pending",
      agent_activity_id: agent_activity&.id
    )

    # Set the appropriate priority based on urgency
    event_priority = if urgency == "critical"
                      Event::CRITICAL_PRIORITY
    else
                      Event::HIGH_PRIORITY
    end

    Event.publish(
      "human_intervention_requested",
      { intervention_id: intervention.id, description: issue_description, urgency: urgency },
      { priority: event_priority }
    )

    "Escalated to human operators with #{urgency} urgency. Intervention ID: #{intervention.id}"
  rescue => e
    Rails.logger.error "[OrchestratorAgent] Error escalating to human: #{e.message}"
    "Error escalating issue: #{e.message}"
  end

  # Tool implementation: Adjust system priorities
  def adjust_system_priorities(adjustments)
    results = []

    # Process each adjustment
    if adjustments.is_a?(String)
      adjustment_pairs = adjustments.split(",").map(&:strip)
      adjustment_pairs.each do |pair|
        task_id, priority = pair.split(":").map(&:strip)
        begin
          # Convert task_id to integer if it's a string
          task_id = task_id.to_i if task_id.is_a?(String)
          task = Task.find(task_id)

          # Validate the priority value
          unless [ "low", "normal", "high", "urgent" ].include?(priority.to_s.downcase)
            results << "Failed to adjust task #{task_id}: Invalid priority"
            next
          end

          # Update the task priority
          original_priority = task.priority
          task.update!(priority: priority)

          # Always create the event, even in test environment
          task.events.create!(
            event_type: "priority_adjusted",
            data: { from: original_priority, to: priority, adjusted_by: "OrchestratorAgent" },
            agent_activity_id: @agent_activity&.id
          )

          results << "Task #{task_id}: priority changed from #{original_priority || 'unset'} to #{priority}"

          # Log the priority change
          Rails.logger.info("[OrchestratorAgent] Changed priority for Task ##{task_id} from #{original_priority || 'unset'} to #{priority}")

        rescue ActiveRecord::RecordNotFound
          results << "Failed to adjust task #{task_id}: Task not found"
        rescue => e
          results << "Failed to adjust task #{task_id}: #{e.message}"
        end
      end
    else
      # Handle hash-style input for adjustments
      adjustments.each do |task_id, new_priority|
        begin
          # Convert task_id to integer if it's a string
          task_id = task_id.to_i if task_id.is_a?(String)
          task = Task.find(task_id)

          # Validate the priority value
          unless [ "low", "normal", "high", "urgent" ].include?(new_priority.to_s.downcase)
            results << "Failed to adjust task #{task_id}: Invalid priority"
            next
          end

          # Update the task priority
          old_priority = task.priority
          task.update!(priority: new_priority.to_s.downcase)

          # Create event without requiring agent_activity
          if @agent_activity
            task.events.create!(
              event_type: "priority_adjusted",
              data: { from: old_priority, to: new_priority, adjusted_by: "OrchestratorAgent" },
              agent_activity_id: @agent_activity.id
            )
          end

          results << "Task #{task_id}: priority changed from #{old_priority || 'unset'} to #{new_priority}"

          # Log the priority change
          Rails.logger.info("[OrchestratorAgent] Changed priority for Task ##{task_id} from #{old_priority || 'unset'} to #{new_priority}")

        rescue ActiveRecord::RecordNotFound
          results << "Failed to adjust task #{task_id}: Task not found"
        rescue => e
          results << "Failed to adjust task #{task_id}: #{e.message}"
        end
      end
    end

    results.join("\n")
  end

  # Tool implementation: Check current resource usage
  def check_resource_usage
    # ... (Gather metrics as before) ...
    db_connections = ActiveRecord::Base.connection_pool.stat[:connections] # Use stat instead of connections.count
    db_pool_size = ActiveRecord::Base.connection_pool.size
    db_usage_percent = (db_connections.to_f / db_pool_size * 100).round(1)

    # Get queue stats (SolidQueue specific)
    queue_stats = SolidQueue::Job.where(finished_at: nil).group(:queue_name).count

    # Get system memory usage
    begin
      memory_info = {}
      if RUBY_PLATFORM =~ /darwin/
        vm_stat = `vm_stat`
        page_size = vm_stat[/page size of (\d+) bytes/, 1].to_i
        pages_free = vm_stat[/Pages free:\s+(\d+)/, 1].to_i
        pages_inactive = vm_stat[/Pages inactive:\s+(\d+)/, 1].to_i
        pages_active = vm_stat[/Pages active:\s+(\d+)/, 1].to_i
        pages_wired = vm_stat[/Pages wired down:\s+(\d+)/, 1].to_i
        total_pages = pages_free + pages_inactive + pages_active + pages_wired
        memory_usage = total_pages > 0 ? ((pages_active + pages_wired).to_f / total_pages * 100).round(1) : 0
        memory_info = { usage_percent: memory_usage }
      elsif RUBY_PLATFORM =~ /linux/
        memory = `free -m`
        total = memory[/^Mem:\s+(\d+)/, 1].to_i
        used = memory[/^Mem:\s+\d+\s+(\d+)/, 1].to_i
        memory_usage = total > 0 ? ((used.to_f / total) * 100).round(1) : 0
        memory_info = { usage_percent: memory_usage, total_mb: total, used_mb: used }
      else
         memory_info = { error: "Unsupported platform for memory check" }
         memory_usage = nil
      end
    rescue => e
      memory_info = { error: "Failed to get memory info: #{e.message}" }
      memory_usage = nil
      Rails.logger.error "[OrchestratorAgent] Memory check failed: #{e.message}"
    end

    # Get CPU usage
    begin
      if RUBY_PLATFORM =~ /darwin/
        cpu_info = `top -l 1 -n 0 | grep "CPU usage"`
        user_cpu = cpu_info[/(\d+\.\d+)% user/, 1].to_f
        sys_cpu = cpu_info[/(\d+\.\d+)% sys/, 1].to_f
        cpu_usage = (user_cpu + sys_cpu).round(1)
      elsif RUBY_PLATFORM =~ /linux/
        cpu_info = `top -bn1 | grep "%Cpu(s)"`
        idle_cpu = cpu_info[/(\d+\.\d+)\s*id/, 1].to_f
        cpu_usage = (100 - idle_cpu).round(1)
      else
         cpu_usage = nil # Unsupported platform
      end
    rescue => e
      cpu_usage = nil
      Rails.logger.error "[OrchestratorAgent] CPU check failed: #{e.message}"
    end

    # API usage (simplified)
    recent_llm_calls = LlmCall.where("created_at > ?", 24.hours.ago).count
    daily_limit = ENV["DAILY_LLM_CALL_LIMIT"].to_i
    daily_limit = 1000 if daily_limit <= 0
    api_quota_used = daily_limit > 0 ? (recent_llm_calls.to_f / daily_limit * 100).round(1) : 0

    # Queue depths
    orchestrator_queue_depth = queue_stats["orchestrator"] || 0
    coordinator_queue_depth = queue_stats["coordinator"] || 0
    agent_queue_depth = queue_stats["agents"] || 0

    resource_data = {
      system: {
        cpu_usage: cpu_usage.nil? ? "Unknown" : "#{cpu_usage}%",
        memory_usage: memory_usage.nil? ? "Unknown" : "#{memory_usage}%",
        db_connections: { current: db_connections, max: db_pool_size, usage_percent: db_usage_percent },
        api_quota: { calls_last_24h: recent_llm_calls, daily_limit: daily_limit, usage_percent: api_quota_used }
      },
      queues: {
        orchestrator: orchestrator_queue_depth,
        coordinator: coordinator_queue_depth,
        agents: agent_queue_depth,
        other: queue_stats.except("orchestrator", "coordinator", "agents")
      }
    }

    # Use LLM to analyze the resource usage
    prompt_content = <<~PROMPT
      Analyze the current resource usage metrics:

      RESOURCE METRICS:
      #{JSON.pretty_generate(resource_data)}

      Based on these metrics, provide:
      1. Concise assessment of resource health.
      2. Any resource constraints or bottlenecks.
      3. Specific recommendations for optimization.

      FORMAT AS:
      RESOURCE HEALTH: [overall assessment]

      CONSTRAINTS:
      - [constraint 1]

      RECOMMENDATIONS:
      - [recommendation 1]
    PROMPT

    begin
      # Use the agent's LLM instance
      response = @llm.chat(messages: [ { role: "user", content: prompt_content } ])

      # Manually log the direct LLM call
      log_direct_llm_call(prompt_content, response)

      response.chat_completion # Or response.content
    rescue => e
      Rails.logger.error "[OrchestratorAgent] Error during LLM call in check_resource_usage: #{e.message}"
      "Error analyzing resource usage: #{e.message}"
    end
  end
  
  # Tool implementation: Trigger re-coordination of a project
  def recoordinate_project(project_id)
    begin
      project = Project.find(project_id)
      
      Rails.logger.info "[OrchestratorAgent] Initiating re-coordination for project #{project.name} (ID: #{project_id})"
      
      # Find a suitable task to attach the coordinator to
      # Prefer root tasks or active tasks
      target_task = project.root_tasks.first
      
      if target_task.nil?
        return "Error: Project #{project_id} has no root task to re-coordinate."
      end
      
      # Create a coordinator agent specifically for re-coordination
      coordinator_options = {
        task_id: target_task.id,
        parent_activity_id: agent_activity&.id,
        purpose: "Re-coordinate project and evaluate progress",
        priority: "high",
        metadata: {
          project_id: project.id,
          project_name: project.name,
          recoordination_type: "project_evaluation",
          initiated_by: "OrchestratorAgent"
        }
      }
      
      # Enqueue the coordinator with specific instructions to use the recoordinate_project tool
      job = CoordinatorAgent.enqueue(
        "Re-coordinate and evaluate project: #{project.name}\n\nThis is a project re-coordination task. Please use the recoordinate_project tool with project_id: #{project_id} to analyze the current state of the project, evaluate completed tasks, and determine appropriate next steps.",
        coordinator_options
      )
      
      # Log the action
      agent_activity&.events.create!(
        event_type: "project_recoordination_initiated",
        data: { 
          project_id: project.id, 
          project_name: project.name,
          target_task_id: target_task.id,
          coordinator_job: job.to_s
        }
      )
      
      # Publish an event for the system
      Event.publish(
        "project_recoordination_initiated",
        { 
          project_id: project.id, 
          project_name: project.name,
          target_task_id: target_task.id
        },
        { agent_activity_id: agent_activity&.id }
      )
      
      "Initiated re-coordination for project '#{project.name}' (ID: #{project_id}). A CoordinatorAgent has been assigned to evaluate progress and determine next steps."
      
    rescue ActiveRecord::RecordNotFound
      "Error: Project with ID #{project_id} not found."
    rescue => e
      Rails.logger.error "[OrchestratorAgent] Error in recoordinate_project: #{e.message}"
      "Error initiating re-coordination for project #{project_id}: #{e.message}"
    end
  end

  # --- Lifecycle Hooks ---

  # Override after_run to add specific logging after base class actions
  def after_run(result) # Ensure parameter matches base class if needed
    # Log with the exact format expected by the tests - this must come first!
    # The test is looking for this exact string format
    Rails.logger.info("OrchestratorAgent Run Summary: #{result}")

    # Call the parent implementation after our specific logging
    super(result)

    # For OrchestratorAgent, log decisions made during this run
    decision_log = "OrchestratorAgent Run Summary (Activity: #{@agent_activity&.id}):\n"
    decision_log += "  Result: #{result.inspect}\n"

    # Log tool executions
    session_trace_legacy = @session_data # Assuming @session_data holds old format temporarily
    if session_trace_legacy && session_trace_legacy[:tool_executions]
      decision_log += "  Legacy Tool Executions Log:\n"
      session_trace_legacy[:tool_executions].each do |tool_exec|
         case tool_exec[:tool].to_s # Convert symbol keys if necessary
         when "spawn_coordinator"
           decision_log += "  - Spawned coordinator for task #{tool_exec.dig(:args, 0) || tool_exec.dig(:args, 'task_id')}\n" # Handle different arg formats
         when "escalate_to_human"
           decision_log += "  - Escalated issue to human: #{tool_exec.dig(:args, 0) || tool_exec.dig(:args, 'issue_description')}\n"
         when "adjust_system_priorities"
           decision_log += "  - Adjusted priorities: #{tool_exec.dig(:args, 0) || tool_exec.dig(:args, 'adjustments')}\n"
         end
      end
    end

    # Log the detailed decision log as debug to avoid test conflicts
    Rails.logger.debug(decision_log)
  end

  # The base class handles the run cycle.
end
