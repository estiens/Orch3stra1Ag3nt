# CoordinatorAgent: Manages task decomposition and subtask delegation
class CoordinatorAgent < BaseAgent
  include EventSubscriber

  # Define a higher-priority queue
  def self.queue_name
    :coordinator
  end

  # Limit concurrency to 3 coordinators at a time
  def self.concurrency_limit
    3
  end

  # Subscribe to relevant events
  subscribe_to "subtask_completed", :handle_subtask_completed
  subscribe_to "subtask_failed", :handle_subtask_failed
  subscribe_to "task_waiting_on_human", :handle_human_input_required

  # Tools that the coordinator can use
  tool :analyze_task, "Analyze the task and break it down into subtasks"
  tool :create_subtask, "Create a new subtask"
  tool :assign_subtask, "Assign a subtask to an appropriate agent"
  tool :check_subtasks, "Check the status of subtasks"
  tool :update_task_status, "Update the status of the current task"
  tool :request_human_input, "Request input from a human to proceed"
  tool :mark_task_complete, "Mark the main task as complete when all subtasks are done"

  # Handle subtask completed event
  def handle_subtask_completed(event)
    subtask_id = event.data["subtask_id"]
    return if subtask_id.blank?

    subtask = Task.find(subtask_id)
    parent_task = subtask.parent

    run("Handle completed subtask and determine next steps:\n" +
        "Subtask: #{subtask.title}\n" +
        "Parent Task: #{parent_task.title}\n" +
        "Result: #{event.data['result']}")
  end

  # Handle subtask failed event
  def handle_subtask_failed(event)
    subtask_id = event.data["subtask_id"]
    return if subtask_id.blank?

    subtask = Task.find(subtask_id)
    parent_task = subtask.parent
    error = event.data["error"] || "Unknown error"

    run("Handle failed subtask and determine recovery actions:\n" +
        "Subtask: #{subtask.title}\n" +
        "Parent Task: #{parent_task.title}\n" +
        "Error: #{error}")
  end

  # Handle human input required
  def handle_human_input_required(event)
    task_id = event.data["task_id"]
    return if task_id.blank?

    task = Task.find(task_id)
    question = event.data["question"]

    run("Handle task waiting for human input:\n" +
        "Task: #{task.title}\n" +
        "Question: #{question}\n" +
        "Determine if there are alternative approaches or if we must wait.")
  end

  # Implement the tool methods
  def analyze_task(task_description)
    # Create a simple prompt for the LLM to break down the task
    prompt = <<~PROMPT
      I need to break down the following task into clear, manageable subtasks:

      TASK: #{task_description}

      Please analyze this task and break it down into 3-5 well-defined subtasks that can be delegated to specialized agents.
      For each subtask, provide:
      1. A clear title (1-5 words)
      2. A detailed description of what needs to be done
      3. Suggested priority (high, normal, or low)

      FORMAT YOUR RESPONSE LIKE THIS:

      Subtask 1: [TITLE]
      Description: [DETAILED DESCRIPTION]
      Priority: [PRIORITY]

      Subtask 2: [TITLE]
      Description: [DETAILED DESCRIPTION]
      Priority: [PRIORITY]

      ...and so on.
    PROMPT

    # Use a thinking model for this complex reasoning task
    thinking_model = Regent::LLM.new(REGENT_MODEL_DEFAULTS[:thinking], temperature: 0.3)
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

  def create_subtask(title, description, priority = "normal")
    # Validate that we have a parent task
    unless task
      return "Error: No parent task available to create subtask"
    end

    # Create the subtask with parent association
    subtask = task.subtasks.create!(
      title: title,
      description: description,
      priority: priority,
      state: "pending"
    )

    # Create an event for the new subtask
    agent_activity.events.create!(
      event_type: "subtask_created",
      data: {
        subtask_id: subtask.id,
        parent_id: task.id,
        title: title
      }
    )

    # Also publish this as a system event
    Event.publish(
      "subtask_created",
      {
        subtask_id: subtask.id,
        parent_id: task.id,
        title: title
      }
    )

    "Created subtask '#{title}' with ID #{subtask.id} and priority '#{priority}'"
  end

  def assign_subtask(subtask_id, agent_type, purpose = nil)
    # Find the subtask
    subtask = Task.find(subtask_id)

    # Resolve the agent class name
    agent_class_name = agent_type.end_with?("Agent") ? agent_type : "#{agent_type.camelize}Agent"

    begin
      # Try to get the agent class
      agent_class = agent_class_name.constantize

      # Ensure it's a BaseAgent subclass
      unless agent_class < BaseAgent
        return "Error: #{agent_class_name} is not a valid agent type"
      end

      # Create options for the agent
      agent_options = {
        task_id: subtask.id,
        parent_activity_id: agent_activity.id,
        purpose: purpose || "Execute subtask: #{subtask.title}"
      }

      # Enqueue the agent job
      agent_class.enqueue(
        "Execute subtask: #{subtask.title}\n\n#{subtask.description}",
        agent_options
      )

      # Update subtask state to active
      subtask.activate! if subtask.may_activate?

      # Create event for assignment
      agent_activity.events.create!(
        event_type: "subtask_assigned",
        data: {
          subtask_id: subtask.id,
          agent_type: agent_class_name
        }
      )

      "Assigned subtask #{subtask_id} to #{agent_class_name}"
    rescue NameError => e
      "Error: Agent type '#{agent_class_name}' not found: #{e.message}"
    rescue => e
      "Error assigning subtask: #{e.message}"
    end
  end

  def check_subtasks
    return "Error: No parent task available" unless task

    # Get all subtasks for the current task
    subtasks = task.subtasks

    if subtasks.empty?
      return "No subtasks found for task #{task.id}"
    end

    # Compile status report
    report = "Subtask Status Report for Task #{task.id}:\n\n"

    # Group by state
    by_state = subtasks.group_by(&:state)

    # Summary counts
    report += "Summary:\n"
    report += "- Total subtasks: #{subtasks.count}\n"
    report += "- Pending: #{by_state['pending']&.count || 0}\n"
    report += "- Active: #{by_state['active']&.count || 0}\n"
    report += "- Waiting on human: #{by_state['waiting_on_human']&.count || 0}\n"
    report += "- Completed: #{by_state['completed']&.count || 0}\n"
    report += "- Failed: #{by_state['failed']&.count || 0}\n\n"

    # Detailed listing
    report += "Details:\n"
    subtasks.each do |subtask|
      report += "- [#{subtask.state.upcase}] #{subtask.id}: #{subtask.title}\n"
    end

    # Check if all are complete
    if subtasks.all? { |s| s.state == "completed" }
      report += "\nAll subtasks are completed! The main task can be marked as complete."
    end

    report
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

  def request_human_input(question, required = true)
    # Create a human input request
    input_request = HumanInputRequest.create!(
      task: task,
      question: question,
      required: required,
      status: "pending",
      agent_activity: agent_activity
    )

    # If this input is required, change task state
    if required && task.may_wait_on_human?
      task.wait_on_human!
    end

    # Publish event for dashboard notification
    Event.publish(
      "human_input_requested",
      {
        request_id: input_request.id,
        task_id: task.id,
        question: question,
        required: required
      },
      priority: required ? Event::HIGH_PRIORITY : Event::NORMAL_PRIORITY
    )

    if required
      "Task is now waiting for required human input: '#{question}'"
    else
      "Optional human input requested: '#{question}'. Task will continue processing."
    end
  end

  def mark_task_complete(summary = nil)
    unless task
      return "Error: No task available to mark complete"
    end

    # Check if all subtasks are complete
    incomplete_subtasks = task.subtasks.where.not(state: "completed")

    if incomplete_subtasks.any?
      incomplete_count = incomplete_subtasks.count
      return "Cannot complete task - #{incomplete_count} subtasks are still incomplete"
    end

    # Update task with summary if provided
    task.update(result: summary) if summary.present?

    # Mark as complete
    if task.may_complete?
      task.complete!

      # Publish completion event
      Event.publish(
        "task_completed",
        {
          task_id: task.id,
          result: summary
        }
      )

      "Task #{task.id} marked as complete with summary: #{summary || 'No summary provided'}"
    else
      "Task cannot be completed from its current state: #{task.state}"
    end
  end

  # Override the after_run method to check if all subtasks are complete
  def after_run
    super

    # Skip if no task or no activity
    return unless task && agent_activity

    if task.subtasks.any?
      completed_count = task.subtasks.where(state: :completed).count
      total_count = task.subtasks.count

      if completed_count == total_count
        # All subtasks completed - mark the main task as completed if not done yet
        if task.may_complete?
          task.complete!

          agent_activity.events.create!(
            event_type: "task_completed",
            data: {
              task_id: task.id,
              completed_by: "CoordinatorAgent",
              message: "All subtasks completed automatically"
            }
          )

          Rails.logger.info("All subtasks completed (#{completed_count}/#{total_count}) - marking task #{task.id} as complete")
        end
      else
        Rails.logger.info("Waiting on subtasks (#{completed_count}/#{total_count}) for task #{task.id}")
      end
    end
  rescue => e
    Rails.logger.error("Error in CoordinatorAgent after_run: #{e.message}")
  end
end
