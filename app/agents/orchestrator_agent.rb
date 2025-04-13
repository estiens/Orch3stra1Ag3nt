# OrchestratorAgent: Top-level agent that manages the system and spawns other agents
class OrchestratorAgent < BaseAgent
  # Define a higher-priority queue
  def self.queue_name
    :orchestrator
  end

  # Limit concurrency to 1 orchestrator at a time
  def self.concurrency_limit
    1
  end

  # Tools that the orchestrator can use
  tool :check_pending_tasks, "Check for any pending tasks that need processing"
  tool :spawn_coordinator, "Spawn a CoordinatorAgent to manage a specific task"
  tool :check_system_resources, "Check system resource utilization"
  tool :summarize_agent_activities, "Get a summary of recent agent activities"

  # Implement the tool methods
  def check_pending_tasks
    # Query for pending tasks
    pending_tasks = Task.where(state: :pending).limit(5)

    if pending_tasks.any?
      tasks_info = pending_tasks.map do |task|
        "Task ##{task.id}: #{task.title} (created at #{task.created_at})"
      end.join("\n")

      "Found #{pending_tasks.count} pending tasks:\n#{tasks_info}"
    else
      "No pending tasks found."
    end
  end

  def spawn_coordinator(task_id)
    # Find the task
    task = Task.find_by(id: task_id)

    if task.nil?
      return "Error: Task ##{task_id} not found."
    end

    # Create coordinator job for this task
    coordinator_options = {
      task_id: task.id,
      purpose: "Manage and coordinate subtasks for: #{task.title}"
    }

    CoordinatorAgent.enqueue("Analyze and process task: #{task.title}", coordinator_options)

    "CoordinatorAgent spawned for Task ##{task_id}: #{task.title}"
  end

  def check_system_resources
    # Get queue stats
    queues_info = SolidQueue::Job.group(:queue_name).count.map do |queue, count|
      "Queue '#{queue}': #{count} jobs"
    end.join("\n")

    running_info = SolidQueue::Job
      .joins(:claimed_execution)
      .group(:queue_name)
      .count
      .map do |queue, count|
        "Running on '#{queue}': #{count} jobs"
      end.join("\n")

    memory_usage = `ps -o rss= -p #{Process.pid}`.to_i / 1024.0

    """
    System Status:
    -------------
    Queue Counts:
    #{queues_info}

    Running Jobs:
    #{running_info}

    Memory usage (Rails): #{memory_usage.round(2)} MB
    """
  end

  def summarize_agent_activities
    # Get recent activity stats
    recent = AgentActivity.where("created_at > ?", 1.hour.ago)

    by_status = recent.group(:status).count.map do |status, count|
      "#{status}: #{count}"
    end.join(", ")

    by_agent = recent.group(:agent_type).count.map do |agent, count|
      "#{agent.demodulize}: #{count}"
    end.join(", ")

    """
    Agent Activity Summary (last hour):
    ---------------------------------
    Total activities: #{recent.count}

    By status: #{by_status}
    By agent type: #{by_agent}
    """
  end

  # Configure for scheduled execution
  def self.setup_hourly_check
    configure_recurring(
      key: "hourly_orchestration",
      schedule: "every hour",
      prompt: "Check the system for pending tasks and perform system maintenance.",
      options: { task_id: 1 } # Replace with a real system monitoring task
    )
  end
end
