# ResearchService: Service to initiate and manage research tasks
# Provides an interface for starting research and tracking progress
class ResearchService
  # Start a new research task
  # @param title [String] The research question or title
  # @param description [String] Detailed description of the research task
  # @param priority [String] Priority level (high, normal, low)
  # @param options [Hash] Additional options
  # @return [Task] The created research task
  def self.start_research(title, description, priority = "normal", options = {})
    # Create the parent research task
    task = Task.create!(
      title: title,
      description: description,
      priority: priority,
      state: "pending",
      task_type: "research",
      metadata: {
        research_initiated_at: Time.current,
        research_options: options
      }
    )

    # Publish the research task created event to trigger the coordinator
    Event.publish(
      "research_task_created",
      {
        task_id: task.id,
        title: title,
        priority: priority
      },
      priority: priority == "high" ? Event::HIGH_PRIORITY : Event::NORMAL_PRIORITY
    )

    # Log the research initiation
    Rails.logger.info("Research task initiated: '#{title}' (ID: #{task.id}, Priority: #{priority})")

    # Return the created task
    task
  end

  # Get the status of a research task including subtasks
  # @param task_id [Integer] The ID of the research task
  # @return [Hash] Status information about the research task
  def self.research_status(task_id)
    task = Task.find(task_id)
    subtasks = task.subtasks

    # Calculate progress
    total_subtasks = subtasks.count
    completed_subtasks = subtasks.where(state: "completed").count
    progress_percentage = total_subtasks > 0 ? (completed_subtasks.to_f / total_subtasks * 100).round : 0

    # Compile status by subtask
    subtask_details = subtasks.map do |subtask|
      {
        id: subtask.id,
        title: subtask.title,
        state: subtask.state,
        agent_type: subtask.metadata&.dig("agent_type"),
        created_at: subtask.created_at,
        updated_at: subtask.updated_at
      }
    end

    # Build the status report
    {
      task: {
        id: task.id,
        title: task.title,
        state: task.state,
        created_at: task.created_at,
        updated_at: task.updated_at
      },
      progress: {
        total_subtasks: total_subtasks,
        completed_subtasks: completed_subtasks,
        progress_percentage: progress_percentage
      },
      subtasks: subtask_details,
      result: task.result
    }
  end

  # Get comprehensive results from a completed research task
  # @param task_id [Integer] The ID of the research task
  # @return [Hash] Detailed results from the research
  def self.research_results(task_id)
    task = Task.find(task_id)
    subtasks = task.subtasks

    # Get all subtask results
    subtask_results = subtasks.where(state: "completed").map do |subtask|
      {
        title: subtask.title,
        result: subtask.result,
        agent_type: subtask.metadata&.dig("agent_type"),
        completed_at: subtask.updated_at
      }
    end

    # Build the results report
    {
      task: {
        id: task.id,
        title: task.title,
        description: task.description,
        state: task.state,
        created_at: task.created_at,
        completed_at: task.updated_at
      },
      summary: task.result,
      detailed_results: subtask_results
    }
  end

  # Create a research task and immediately spawn a coordinator for it
  # This is useful for testing or when you want immediate processing
  # @param title [String] The research question or title
  # @param description [String] Detailed description of the research task
  # @param priority [String] Priority level (high, normal, low)
  # @return [Task] The created research task
  def self.immediate_research(title, description, priority = "normal")
    # Create the task first
    task = start_research(title, description, priority)

    # Create options for the coordinator
    options = {
      task_id: task.id,
      purpose: "Coordinate research: #{title}"
    }

    # Directly enqueue a research coordinator
    ResearchCoordinatorAgent.enqueue(
      "Coordinate research task: #{title}\n\n#{description}",
      options
    )

    # Return the task
    task
  end

  # Helper to find all research tasks
  # @param include_completed [Boolean] Whether to include completed tasks
  # @return [ActiveRecord::Relation] The matching tasks
  def self.all_research_tasks(include_completed = true)
    query = Task.where(task_type: "research")
    query = query.where.not(state: "completed") unless include_completed
    query.order(created_at: :desc)
  end
end
