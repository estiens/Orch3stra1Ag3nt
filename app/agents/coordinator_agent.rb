# CoordinatorAgent: Strategically decomposes tasks and manages execution flow
class CoordinatorAgent < BaseAgent
  include EventSubscriber
  include Coordinator::EventHandlers
  include Coordinator::Tools::TaskManagement
  include Coordinator::Tools::StatusManagement
  include Coordinator::Tools::ProjectManagement
  include Coordinator::Helpers
  include Coordinator::Prompts

  # Define a higher-priority queue
  def self.queue_name
    :coordinator
  end

  # Limit concurrency to prevent resource contention
  def self.concurrency_limit
    3
  end

  # Subscribe to relevant events for real-time coordination using dot notation format
  subscribe_to "subtask.completed", :handle_subtask_completed
  subscribe_to "subtask.failed", :handle_subtask_failed
  subscribe_to "task.waiting_on_human", :handle_human_input_required
  subscribe_to "tool_execution.finished", :handle_tool_execution
  subscribe_to "agent.completed", :handle_agent_completed
  subscribe_to "human_input.provided", :handle_human_input_provided

  # Subscribe to project-related events
  subscribe_to "project.created", :handle_project_created
  subscribe_to "project.activated", :handle_project_activated
  subscribe_to "project.stalled", :handle_project_stalled
  subscribe_to "project.recoordination_requested", :handle_project_recoordination
  subscribe_to "project.paused", :handle_project_paused
  subscribe_to "project.resumed", :handle_project_resumed

  # --- Tools with Explicit Parameter Documentation ---
  tool :analyze_task, "Initial planning: Break down a complex task into logical subtasks with dependencies. Takes (task_description: <full task details>)" do |task_description:|
    analyze_task(task_description)
  end

  tool :create_subtask, "Create a well-defined subtask to be assigned to an agent. Takes (title: <concise title>, description: <detailed instructions>, priority: <high/normal/low>)" do |title:, description:, priority: "normal"|
    create_subtask(title, description, priority)
  end

  tool :assign_subtask, "Delegate a subtask to the most suitable agent type. Takes (subtask_id: <ID number>, agent_type: <agent class name>, purpose: <optional context>)" do |subtask_id:, agent_type:, purpose: nil|
    assign_subtask(subtask_id, agent_type, purpose)
  end

  tool :create_sub_coordinator, "Create another coordinator agent to handle a complex subtask that needs further decomposition. Takes (subtask_id: <ID number>, purpose: <optional context>)" do |subtask_id:, purpose: nil|
    create_sub_coordinator(subtask_id, purpose)
  end

  tool :check_subtasks, "Monitor progress of all subtasks for the current task. Takes no parameters." do
    check_subtasks
  end

  tool :update_task_status, "Record important status updates about task progress. Takes (status_message: <progress update>)" do |status_message:|
    update_task_status(status_message)
  end

  tool :request_human_input, "Ask for human intervention when needed. Takes (question: <specific question>, required: <true/false>)" do |question:, required: true|
    request_human_input(question, required)
  end

  tool :mark_task_complete, "Finalize task when all objectives are met. Takes (summary: <optional final report>)" do |summary: nil|
    mark_task_complete(summary)
  end

  tool :recoordinate_project, "Analyze project progress, evaluate completed tasks, and determine next steps. Takes (project_id: <ID number>)" do |project_id:|
    recoordinate_project(project_id)
  end
  # --- End Tools ---

  # --- Core Logic ---
  # Intelligent workflow management based on task state
  def run(input = nil)
    before_run(input)

    unless task
      result = "CoordinatorAgent Error: Agent is not associated with a task."
      Rails.logger.error result
      @session_data[:output] = result
      after_run(result)
      return result
    end

    # Parse input context if provided
    context = input.is_a?(Hash) ? input[:context] : nil
    event_type = context&.dig(:event_type)

    # Check if this is a sub-coordinator and get nesting level
    is_sub_coordinator = task.metadata&.dig("is_sub_coordinator") == true
    nesting_level = task.metadata&.dig("nesting_level") || 0

    # Check if this is a project coordination task
    is_project_coordination = (task.task_type == "coordination" && task.project_id.present?)

    # Log the coordinator start with context
    coordinator_type = if is_project_coordination
                       "Project Coordinator"
    elsif is_sub_coordinator
                       "Sub-Coordinator (Level #{nesting_level})"
    else
                       "Root Coordinator"
    end

    Rails.logger.info "[#{coordinator_type}-#{task.id}] Starting run with event_type: #{event_type || 'none'}"

    result_message = nil

    begin
      # Different logic flows based on task state and context
      if event_type == "subtask_failed"
        # Handle failed subtask
        subtask_id = context[:subtask_id]
        error = context[:error]
        result_message = handle_failed_subtask(subtask_id, error)
      elsif event_type == "subtask_completed"
        # Process completed subtask and determine next actions
        subtask_id = context[:subtask_id]
        result = context[:result]
        result_message = process_completed_subtask(subtask_id, result)
      elsif event_type == "human_input_required"
        # Handle human input requirement
        question = context[:question]
        result_message = handle_human_input_requirement(question)
      elsif event_type == "task_resumed"
        # Handle task resumption after being paused
        result_message = "Task resumed. Evaluating current progress and next steps."
        result_message = evaluate_current_progress
      elsif event_type == "project_recoordination_requested" && is_project_coordination
        # Handle project recoordination if this is a project coordinator
        project_id = task.project_id
        Rails.logger.info "[Project Coordinator-#{task.id}] Recoordinating project #{project_id}"
        result_message = execute_tool(:recoordinate_project, project_id: project_id)
      elsif task.reload.subtasks.empty? # Check if subtasks are *actually* empty
        # Initial decomposition for new tasks
        if is_project_coordination
          # For project coordinators
          Rails.logger.info "[Project Coordinator-#{task.id}] Performing initial project decomposition"
          update_task_status("Starting decomposition for project: #{task.project.name}")
          result_message = perform_initial_task_decomposition
        elsif is_sub_coordinator
          # For sub-coordinators, log the nesting level
          Rails.logger.info "[Sub-Coordinator-#{task.id}] Performing decomposition at nesting level #{nesting_level}"
          update_task_status("Starting decomposition as a level #{nesting_level} sub-coordinator")
          result_message = perform_initial_task_decomposition
        else
          # Regular coordinator
          result_message = perform_initial_task_decomposition
        end
      else
        # General progress check and next steps
        result_message = evaluate_current_progress
      end

    rescue => e
      handle_run_error(e)
      raise
    end

    @session_data[:output] = result_message

    # Log completion with context
    Rails.logger.info "[#{coordinator_type}-#{task.id}] Completed run with result: #{result_message.truncate(100)}"

    after_run(result_message) # This run finishes, event handlers will trigger next run if needed
    result_message
  end
  # --- End Core Logic ---
end
