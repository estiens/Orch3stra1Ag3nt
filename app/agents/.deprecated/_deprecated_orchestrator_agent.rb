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
  subscribe_to "project_recoordination_requested", :handle_project_recoordination
  subscribe_to "project_paused", :handle_project_paused
  subscribe_to "project_resumed", :handle_project_resumed

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

  # Event handler for project recoordination requests
  def handle_project_recoordination(event)
    project_id = event.data["project_id"]
    return if project_id.blank?

    project = Project.find(project_id)
    reason = event.data["reason"] || "Recoordination requested"

    Rails.logger.info "[OrchestratorAgent] Received handle_project_recoordination for #{project.name}. Reason: #{reason}"

    # Trigger re-coordination for the project
    recoordination_result = recoordinate_project(project_id)

    # Log the action
    agent_activity&.events.create!(
      event_type: "project_recoordination_requested_handled",
      data: {
        project_id: project.id,
        project_name: project.name,
        reason: reason,
        recoordination_result: recoordination_result
      }
    )
  end

  # Event handler for paused projects
  def handle_project_paused(event)
    project_id = event.data["project_id"]
    return if project_id.blank?

    project = Project.find(project_id)

    Rails.logger.info "[OrchestratorAgent] Received handle_project_paused for #{project.name}"

    # Log the action
    agent_activity&.events.create!(
      event_type: "project_pause_acknowledged",
      data: {
        project_id: project.id,
        project_name: project.name,
        message: "Project pause acknowledged. No new tasks will be started until resumed."
      }
    )
  end

  # Event handler for resumed projects
  def handle_project_resumed(event)
    project_id = event.data["project_id"]
    return if project_id.blank?

    project = Project.find(project_id)

    Rails.logger.info "[OrchestratorAgent] Received handle_project_resumed for #{project.name}"

    # Trigger re-coordination for the resumed project
    recoordination_result = recoordinate_project(project_id)

    # Log the action
    agent_activity&.events.create!(
      event_type: "project_resume_handled",
      data: {
        project_id: project.id,
        project_name: project.name,
        recoordination_result: recoordination_result,
        message: "Project resumed. Re-coordination initiated to continue progress."
      }
    )
  end

  # --- Core Logic ---
  # Override run to implement orchestrator logic
  def run(input = nil) # Input could be trigger info, but often unused for scheduled runs
    before_run(input)

    result_message = "Orchestrator run completed."
    begin
      Rails.logger.info "[OrchestratorAgent-#{agent_activity&.id}] Starting system analysis..."

      # Parse input context if provided
      context = input.is_a?(Hash) ? input[:context] : nil
      purpose_override = context&.dig(:purpose_override)

      # Log the purpose if provided
      if purpose_override
        Rails.logger.info "[OrchestratorAgent-#{agent_activity&.id}] Run purpose: #{purpose_override}"
      end

      # Always analyze system state
      system_analysis = execute_tool(:analyze_system_state, input)
      Rails.logger.info "[OrchestratorAgent-#{agent_activity&.id}] System Analysis Result:\n#{system_analysis}"

      # Check resource usage
      resource_analysis = execute_tool(:check_resource_usage)
      Rails.logger.info "[OrchestratorAgent-#{agent_activity&.id}] Resource Usage Result:\n#{resource_analysis}"

      # Analyze the results and take appropriate actions
      actions_taken = []

      # Check for coordinator queue depth issues
      if system_analysis.include?("coordinator queue") && system_analysis.include?("high") &&
         (system_analysis.include?("bottleneck") || system_analysis.include?("overloaded"))
        # Adjust priorities of pending coordinator tasks
        priority_adjustments = determine_priority_adjustments("coordinator")
        if priority_adjustments.any?
          adjustment_str = priority_adjustments.map { |id, priority| "#{id}:#{priority}" }.join(", ")
          adjust_result = execute_tool(:adjust_system_priorities, adjustment_str)
          actions_taken << "Adjusted coordinator task priorities: #{adjustment_str}"
        end
      end

      # Check for resource constraints
      if resource_analysis.include?("CONSTRAINTS") &&
         (resource_analysis.include?("critical") || resource_analysis.include?("severe"))
        # Extract the constraints
        constraints = resource_analysis.match(/CONSTRAINTS:\s*(.*?)(?=\n\n|\nRECOMMENDATIONS|\z)/m)&.[](1)
        if constraints
          # Escalate critical resource issues
          escalate_result = execute_tool(:escalate_to_human,
            "CRITICAL RESOURCE CONSTRAINTS: #{constraints.strip}", "high")
          actions_taken << "Escalated critical resource constraints to human operators"
        end
      end

      # Check for stalled projects
      if system_analysis.include?("stalled project") || system_analysis.include?("inactive project")
        # Extract project IDs if available
        project_ids = system_analysis.scan(/project\s+ID[:\s]+(\d+)/i).flatten.uniq

        project_ids.each do |project_id|
          recoordinate_result = execute_tool(:recoordinate_project, project_id)
          actions_taken << "Initiated recoordination for potentially stalled project #{project_id}"
        end
      end

      # If we took actions, summarize them
      if actions_taken.any?
        result_message = "System/Resource analysis complete. Actions taken:\n- #{actions_taken.join("\n- ")}"
      else
        # If analysis indicates concerns but we didn't take specific actions
        if system_analysis.include?("KEY AREAS OF CONCERN") || resource_analysis.include?("CONSTRAINTS")
          concern_summary = "System/Resource concerns detected. Analysis:\nSys: #{system_analysis.split("RECOMMENDED").first}\nRes: #{resource_analysis.split("RECOMMENDATIONS").first}".truncate(500)
          execute_tool(:escalate_to_human, concern_summary, "normal")
          result_message = "System/Resource analysis complete. Concerns found and escalated."
        else
          result_message = "System/Resource analysis complete. No major concerns detected."
        end
      end

    rescue => e
      handle_run_error(e)
      raise # Re-raise after handling
    end

    @session_data[:output] = result_message
    after_run(result_message)
    result_message
  end

  # Helper method to determine priority adjustments for tasks
  def determine_priority_adjustments(queue_type)
    adjustments = {}

    case queue_type
    when "coordinator"
      # Find coordinator tasks that are pending but not yet assigned
      pending_tasks = Task.where(state: "pending")
                          .joins(:metadata)
                          .where("metadata->>'suggested_agent' = ? OR metadata->>'assigned_agent' = ?",
                                "CoordinatorAgent", "CoordinatorAgent")
                          .limit(5)

      # Prioritize tasks with dependencies
      pending_tasks.each do |task|
        # Check if this task has many dependents
        dependent_count = Task.where("depends_on_task_ids @> ARRAY[?]::integer[]", task.id).count

        if dependent_count > 2
          adjustments[task.id] = "high" # Many things depend on this
        elsif task.project_id && Project.find(task.project_id).status == "active"
          adjustments[task.id] = "normal" # Part of an active project
        else
          adjustments[task.id] = "low" # Default
        end
      end
    end

    adjustments
  end
  # --- End Core Logic ---

  # --- Tool Implementations ---
  # (These are now called by the tool blocks above)

  # Tool implementation: Analyze current system state
  def analyze_system_state(query = nil)
    # Gather basic metrics
    active_tasks = Task.active.count
    waiting_tasks = Task.where(state: :waiting_on_human).count
    completed_tasks = Task.where(state: :completed).count
    failed_tasks = Task.where(state: :failed).count

    # Get coordinator-specific metrics
    root_coordinators = Task.where(parent_id: nil).count
    # Use where with JSON query instead of trying to join on metadata
    sub_coordinators = Task.where("metadata->>'is_sub_coordinator' = ?", "true").count

    # Get agent activity metrics
    active_agents = AgentActivity.where(status: "running").count
    agent_types = {}
    begin
      agent_types = AgentActivity.where(status: "running").group(:agent_type).count
    rescue => e
      Rails.logger.error "[OrchestratorAgent] Error getting agent types: #{e.message}"
      agent_types = { error: "Failed to get agent types" }
    end

    # Get queue metrics
    total_queued_jobs = SolidQueue::Job.where(finished_at: nil).count
    queue_stats = {}
    SolidQueue::Job.where(finished_at: nil).group(:queue_name).count.each do |queue, count|
      queue_stats[queue] = count
    end

    # Get error metrics
    # Removed legacy Event.where query for recent errors
    error_summary = "Error summary unavailable (legacy Event model removed)"

    # Get project metrics
    active_projects = Project.where(status: "active").count
    paused_projects = Project.where(status: "paused").count
    completed_projects = Project.where(status: "completed").count

    # Compile all metrics
    system_data = {
      tasks: {
        active: active_tasks,
        waiting_on_human: waiting_tasks,
        completed: completed_tasks,
        failed: failed_tasks
      },
      coordination: {
        root_coordinators: root_coordinators,
        sub_coordinators: sub_coordinators
      },
      agents: {
        active: active_agents,
        by_type: agent_types
      },
      queues: {
        total_pending: total_queued_jobs,
        by_queue: queue_stats
      },
      projects: {
        active: active_projects,
        paused: paused_projects,
        completed: completed_projects
      },
      errors: { recent: error_summary } # Note: Based on removed legacy Event model
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

    # Determine if this is a root task or a subtask
    is_root_task = task.parent_id.nil?
    task_type = is_root_task ? "root task" : "subtask"

    # Create a more specific purpose based on task context
    purpose = if is_root_task && task.project_id
                "Coordinate execution of project root task: #{task.title}"
    elsif is_root_task
                "Coordinate execution of independent task: #{task.title}"
    else
                "Coordinate execution of subtask: #{task.title}"
    end

    options = {
      task_id: task.id,
      parent_activity_id: agent_activity&.id,
      purpose: purpose
    }
    options[:priority] = priority if priority.present?

    # Add project context if available
    if task.project_id
      options[:metadata] = {
        project_id: task.project_id,
        project_name: task.project.name,
        task_type: task_type
      }
    else
      options[:metadata] = { task_type: task_type }
    end

    # Add specific instructions for the coordinator based on task type
    instructions = if is_root_task
                     "This is a #{task.project_id ? 'project root task' : 'standalone task'} that requires strategic decomposition into atomic subtasks. Break it down into highly focused subtasks, and consider using nested coordinators for complex subtasks.\n\n"
    else
                     "This is a subtask that requires further decomposition. Break it down into smaller, more atomic subtasks to ensure precise execution.\n\n"
    end

    instructions += "#{task.title}\n\n#{task.description}"

    CoordinatorAgent.enqueue(instructions, options)

    agent_activity&.events.create!(
      event_type: "coordinator_spawned",
      data: {
        task_id: task.id,
        task_type: task_type,
        priority: priority || "default",
        project_id: task.project_id
      }
    )
    "Spawned CoordinatorAgent for #{task_type} #{task_id} with #{priority || 'default'} priority"

  rescue ActiveRecord::RecordNotFound
    "Error: Task with ID #{task_id} not found."
  rescue => e
    Rails.logger.error "[OrchestratorAgent] Error spawning coordinator: #{e.message}"
    "Error spawning coordinator for task #{task_id}: #{e.message}"
  end

  # Tool implementation: Escalate an issue to human operators
  def escalate_to_human(issue_description, urgency = "normal")
    intervention = HumanInteraction.create!(
      interaction_type: "intervention", # Specify type
      description: issue_description,
      urgency: urgency,
      status: "pending",
      agent_activity_id: agent_activity&.id # Keep existing logic
    )

    # Set the appropriate priority based on urgency
    # Event.publish removed for "human_intervention_requested" as agent is deprecated

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

      # Get project status information
      completed_tasks = project.tasks.where(state: "completed").count
      active_tasks = project.tasks.where(state: "active").count
      pending_tasks = project.tasks.where(state: "pending").count
      failed_tasks = project.tasks.where(state: "failed").count
      total_tasks = project.tasks.count
      completion_percentage = total_tasks > 0 ? ((completed_tasks.to_f / total_tasks) * 100).round : 0

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
          initiated_by: "OrchestratorAgent",
          project_stats: {
            completed_tasks: completed_tasks,
            active_tasks: active_tasks,
            pending_tasks: pending_tasks,
            failed_tasks: failed_tasks,
            total_tasks: total_tasks,
            completion_percentage: completion_percentage
          }
        }
      }

      # Create more detailed instructions based on project status
      instructions = <<~INSTRUCTIONS
        # PROJECT RE-COORDINATION TASK

        ## Project: #{project.name} (ID: #{project_id})

        Current Status:
        - Completion: #{completion_percentage}% (#{completed_tasks}/#{total_tasks} tasks)
        - Active tasks: #{active_tasks}
        - Pending tasks: #{pending_tasks}
        - Failed tasks: #{failed_tasks}

        ## Instructions
        1. Use the recoordinate_project tool with project_id: #{project_id} to analyze the current state
        2. Evaluate completed tasks and their results
        3. Identify any bottlenecks or issues
        4. Determine appropriate next steps
        5. Consider creating new atomic subtasks if needed

        ## Important
        - Focus on creating highly atomic, focused subtasks
        - Use nested coordinators for complex work
        - Ensure all critical paths are being addressed
      INSTRUCTIONS

      # Enqueue the coordinator with specific instructions
      job = CoordinatorAgent.enqueue(instructions, coordinator_options)

      # Log the action
      agent_activity&.events.create!(
        event_type: "project_recoordination_initiated",
        data: {
          project_id: project.id,
          project_name: project.name,
          target_task_id: target_task.id,
          project_stats: coordinator_options[:metadata][:project_stats],
          coordinator_job: job.to_s
        }
      )

      # Event.publish removed for "project_recoordination_initiated" as agent is deprecated

      "Initiated re-coordination for project '#{project.name}' (ID: #{project_id}, #{completion_percentage}% complete). A CoordinatorAgent has been assigned to evaluate progress and determine next steps."

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
