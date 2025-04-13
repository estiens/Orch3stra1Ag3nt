# CoordinatorAgent: Manages task decomposition and subtask delegation
class CoordinatorAgent < BaseAgent
  # Define a higher-priority queue
  def self.queue_name
    :coordinator
  end

  # Limit concurrency to 2 coordinator at a time
  def self.concurrency_limit
    2
  end

  # Tools that the coordinator can use
  tool :analyze_task, "Analyze the task and break it down into subtasks"
  tool :spawn_research_agent, "Spawn a ResearchAgent to gather information"
  tool :spawn_summarizer_agent, "Spawn a SummarizerAgent to summarize information"
  tool :update_task_status, "Update the status of the current task"

  # Implement the tool methods
  def analyze_task(task_description)
    """
    Task Analysis for: #{task_description}

    This appears to require the following steps:
    1. Research the main topic
    2. Gather relevant information
    3. Synthesize findings
    4. Generate a summary

    This task can be broken down into separate research and summarization subtasks.
    """
  end

  def spawn_research_agent(query)
    # Check if a ResearchAgent class exists
    return "ResearchAgent class not found." unless defined?(ResearchAgent)

    # Create a subtask for this research
    subtask = task.subtasks.create!(
      title: "Research: #{query}",
      description: "Research information about #{query}"
    )

    # Create research job for this subtask
    research_options = {
      task_id: subtask.id,
      parent_activity_id: agent_activity.id,
      purpose: "Research information about #{query}"
    }

    # Queue up a research agent job
    ResearchAgent.enqueue("Find information about: #{query}", research_options)

    "ResearchAgent spawned for query: #{query}. Subtask ID: #{subtask.id}"
  end

  def spawn_summarizer_agent(context)
    # Check if a SummarizerAgent class exists
    return "SummarizerAgent class not found." unless defined?(SummarizerAgent)

    # Create a subtask for this summarization
    subtask = task.subtasks.create!(
      title: "Summarize findings",
      description: "Summarize the research findings"
    )

    # Create summarizer job for this subtask
    summarizer_options = {
      task_id: subtask.id,
      parent_activity_id: agent_activity.id,
      purpose: "Summarize research findings"
    }

    # Queue up a summarizer agent job
    SummarizerAgent.enqueue("Summarize the following information: #{context}", summarizer_options)

    "SummarizerAgent spawned for summarization. Subtask ID: #{subtask.id}"
  end

  def update_task_status(status_message)
    task.update!(notes: status_message)

    # Create a status update event
    agent_activity.events.create!(
      event_type: "status_update",
      data: { message: status_message }
    )

    "Task status updated: #{status_message}"
  end

  # Override the after_run method to check if all subtasks are complete
  def after_run
    super

    if task.subtasks.any?
      completed_count = task.subtasks.where(state: :completed).count
      total_count = task.subtasks.count

      if completed_count == total_count
        # All subtasks completed - mark the main task as completed
        task.complete! if task.may_complete?

        Rails.logger.info("All subtasks completed (#{completed_count}/#{total_count}) for task #{task.id}")
      else
        Rails.logger.info("Waiting on subtasks (#{completed_count}/#{total_count}) for task #{task.id}")
      end
    end
  end
end
