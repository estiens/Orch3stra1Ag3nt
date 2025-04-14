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

  # --- Tools ---
  tool :analyze_task, "Analyze the task and break it down into subtasks" do |task_description|
    analyze_task(task_description)
  end

  tool :create_subtask, "Create a new subtask" do |title, description, priority = "normal"|
    create_subtask(title, description, priority)
  end

  tool :assign_subtask, "Assign a subtask to an appropriate agent" do |subtask_id, agent_type, purpose = nil|
    assign_subtask(subtask_id, agent_type, purpose)
  end

  tool :check_subtasks, "Check the status of subtasks" do
    check_subtasks
  end

  tool :update_task_status, "Update the status of the current task" do |status_message|
    update_task_status(status_message)
  end

  tool :request_human_input, "Request input from a human to proceed" do |question, required = true|
    request_human_input(question, required)
  end

  tool :mark_task_complete, "Mark the main task as complete when all subtasks are done" do |summary = nil|
    mark_task_complete(summary)
  end
  # --- End Tools ---

  # --- Event Handlers ---
  # Handle subtask completed event
  def handle_subtask_completed(event)
    subtask_id = event.data["subtask_id"]
    return if subtask_id.blank?

    subtask = Task.find_by(id: subtask_id)
    return unless subtask

    parent_task = subtask.parent
    return unless parent_task && task && parent_task.id == task.id # Ensure event is for *this* coordinator's task

    Rails.logger.info "[CoordinatorAgent #{agent_activity&.id}] Received handle_subtask_completed for Subtask #{subtask_id}."
    # Decide next steps, potentially call check_subtasks or mark_task_complete
    # Or trigger a run: self.run(input: { purpose_override: "Evaluate subtask completion for task #{task.id}" })
  end

  # Handle subtask failed event
  def handle_subtask_failed(event)
    subtask_id = event.data["subtask_id"]
    return if subtask_id.blank?

    subtask = Task.find_by(id: subtask_id)
    return unless subtask

    parent_task = subtask.parent
    return unless parent_task && task && parent_task.id == task.id # Ensure event is for *this* coordinator's task

    error = event.data["error"] || "Unknown error"
    Rails.logger.error "[CoordinatorAgent #{agent_activity&.id}] Received handle_subtask_failed for Subtask #{subtask_id}: #{error}"
    # Decide recovery actions, potentially re-assign or escalate
    # Or trigger a run: self.run(input: { purpose_override: "Handle failed subtask #{subtask_id} for task #{task.id}" })
  end

  # Handle human input required
  def handle_human_input_required(event)
    task_id = event.data["task_id"]
    return if task_id.blank? || task&.id != task_id # Ensure event is for *this* coordinator's task

    question = event.data["question"]
    Rails.logger.warn "[CoordinatorAgent #{agent_activity&.id}] Received handle_human_input_required for Task #{task_id}: #{question}"
    # Decide if alternatives exist or if waiting is necessary
    # Or trigger a run: self.run(input: { purpose_override: "Assess human input requirement for task #{task.id}" })
  end
  # --- End Event Handlers ---

  # --- Tool Implementations ---
  def analyze_task(task_description)
    # Create prompt for the LLM
    prompt_content = <<~PROMPT
      Break down the following task into 3-5 manageable subtasks:

      TASK: #{task_description}

      For each subtask, provide title, description, and priority (high, normal, low).

      FORMAT:
      Subtask 1: [TITLE]
      Description: [DESCRIPTION]
      Priority: [PRIORITY]
      ...
    PROMPT

    # Use the agent's LLM
    begin
      response = @llm.chat(messages: [ { role: "user", content: prompt_content } ])

      # Manually log the LLM call using the helper from BaseAgent
      log_direct_llm_call(prompt_content, response)

      response.chat_completion # Or response.content
    rescue => e
      Rails.logger.error "[CoordinatorAgent] Error during LLM call in analyze_task: #{e.message}"
      "Error analyzing task: #{e.message}"
    end
  end

  def create_subtask(title, description, priority = "normal")
    unless task
      return "Error: Cannot create subtask - Coordinator not associated with a main task."
    end

    begin
      subtask = task.subtasks.create!(
        title: title,
        description: description,
        priority: priority,
        state: "pending" # Initial state
      )

      agent_activity&.events.create!(
        event_type: "subtask_created",
        data: { subtask_id: subtask.id, parent_id: task.id, title: title }
      )

      Event.publish(
        "subtask_created",
        { subtask_id: subtask.id, parent_id: task.id, title: title }
      )

      "Created subtask '#{title}' (ID: #{subtask.id}) for task #{task.id}"
    rescue => e
      Rails.logger.error "[CoordinatorAgent] Error creating subtask: #{e.message}"
      "Error creating subtask '#{title}': #{e.message}"
    end
  end

  def assign_subtask(subtask_id, agent_type, purpose = nil)
    unless task
      return "Error: Cannot assign subtask - Coordinator not associated with a main task."
    end

    begin
      subtask = task.subtasks.find(subtask_id)
    rescue ActiveRecord::RecordNotFound
      return "Error: Subtask with ID #{subtask_id} not found or does not belong to task #{task.id}."
    end

    agent_class_name = agent_type.end_with?("Agent") ? agent_type : "#{agent_type.camelize}Agent"

    begin
      agent_class = agent_class_name.constantize
      unless agent_class < BaseAgent
        return "Error: #{agent_class_name} is not a valid BaseAgent subclass."
      end

      agent_options = {
        task_id: subtask.id,
        parent_activity_id: agent_activity&.id, # Link activity
        purpose: purpose || "Execute subtask: #{subtask.title}"
      }

      # Use the agent class's enqueue method
      agent_class.enqueue(
        "Execute subtask: #{subtask.title}\n\n#{subtask.description}",
        agent_options
      )

      subtask.activate! if subtask.may_activate? # Transition state

      agent_activity&.events.create!(
        event_type: "subtask_assigned",
        data: { subtask_id: subtask.id, agent_type: agent_class_name }
      )

      "Assigned subtask #{subtask_id} ('#{subtask.title}') to #{agent_class_name}."
    rescue NameError
      "Error: Agent type '#{agent_class_name}' not found."
    rescue => e
      Rails.logger.error "[CoordinatorAgent] Error assigning subtask #{subtask_id}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      "Error assigning subtask #{subtask_id}: #{e.message}"
    end
  end

  def check_subtasks
    unless task
      return "Error: Cannot check subtasks - Coordinator not associated with a main task."
    end

    # Reload to get current state
    task.reload
    subtasks = task.subtasks

    if subtasks.empty?
      return "No subtasks found for task #{task.id} ('#{task.title}')."
    end

    report = "Subtask Status Report for Task #{task.id} ('#{task.title}'):\n"
    by_state = subtasks.group_by(&:state)

    report += "- Total: #{subtasks.count}\n"
    Task.state_machines[:state].states.map(&:name).each do |state|
      count = by_state[state.to_s]&.count || 0
      report += "- #{state.to_s.humanize}: #{count}\n" if count > 0 || state.to_s == "pending" # Show pending even if 0
    end
    report += "\nDetails:\n"
    subtasks.each do |st| report += "- [#{st.state.upcase}] ID #{st.id}: #{st.title}\n"; end

    if subtasks.all? { |s| s.state == "completed" }
      report += "\nAll subtasks are completed. You can use mark_task_complete."
    end

    report
  end

  def update_task_status(status_message)
    unless task
      return "Error: Cannot update status - Coordinator not associated with a main task."
    end

    begin
      # Append notes or replace? Let's append for now.
      new_notes = "#{task.notes}\n[#{Time.current.strftime('%Y-%m-%d %H:%M')} Coordinator Update]: #{status_message}".strip
      task.update!(notes: new_notes)

      agent_activity&.events.create!(
        event_type: "status_update",
        data: { task_id: task.id, message: status_message }
      )

      "Task #{task.id} status updated."
    rescue => e
      Rails.logger.error "[CoordinatorAgent] Error updating task status: #{e.message}"
      "Error updating task status: #{e.message}"
    end
  end

  def request_human_input(question, required = true)
    unless task
      return "Error: Cannot request human input - Coordinator not associated with a main task."
    end

    begin
      input_request = HumanInputRequest.create!(
        task: task,
        question: question,
        required: required,
        status: "pending",
        agent_activity: agent_activity
      )

      if required && task.may_wait_on_human?
        task.wait_on_human!
      end

      Event.publish(
        "human_input_requested",
        { request_id: input_request.id, task_id: task.id, question: question, required: required },
        priority: required ? Event::HIGH_PRIORITY : Event::NORMAL_PRIORITY
      )

      message = required ? "Task #{task.id} is now waiting for required human input" : "Optional human input requested for task #{task.id}"
      "#{message}: '#{question}' (Request ID: #{input_request.id})"
    rescue => e
      Rails.logger.error "[CoordinatorAgent] Error requesting human input: #{e.message}"
      "Error requesting human input: #{e.message}"
    end
  end

  def mark_task_complete(summary = nil)
    unless task
      return "Error: Cannot mark complete - Coordinator not associated with a main task."
    end

    task.reload # Ensure we have the latest state
    incomplete_subtasks = task.subtasks.where.not(state: "completed")

    if incomplete_subtasks.any?
      return "Cannot complete task #{task.id} - #{incomplete_subtasks.count} subtasks are incomplete: IDs #{incomplete_subtasks.pluck(:id).join(', ')}."
    end

    begin
      update_data = { result: summary } if summary.present?
      task.update!(update_data) if update_data

      if task.may_complete?
        task.complete!
        Event.publish("task_completed", { task_id: task.id, result: summary })
        "Task #{task.id} ('#{task.title}') marked as complete."
      else
        "Task #{task.id} cannot be completed from its current state: #{task.state}."
      end
    rescue => e
      Rails.logger.error "[CoordinatorAgent] Error marking task complete: #{e.message}"
      "Error marking task #{task.id} complete: #{e.message}"
    end
  end
  # --- End Tool Implementations ---

  # --- Core Logic ---
  # Override run to orchestrate coordinator logic
  def run(input = nil) # Input might be the initial prompt or trigger data
    before_run(input)

    unless task
      result = "CoordinatorAgent Error: Agent is not associated with a task."
      Rails.logger.error result
      @session_data[:output] = result
      after_run(result)
      # No need to raise here, just report the configuration error
      return result
    end

    # Example workflow: Analyze -> Create -> Assign -> Check -> Complete
    result_message = "Coordinator run completed."
    begin
      if task.subtasks.empty?
        Rails.logger.info "[CoordinatorAgent-#{task.id}] No subtasks found; analyzing main task: #{task.title}"
        # Use execute_tool to wrap the call for logging
        analysis_result = execute_tool(:analyze_task, task.description)

        # Parse the LLM response to get subtask details
        subtasks_to_create = parse_subtasks_from_llm(analysis_result)

        if subtasks_to_create.any?
          Rails.logger.info "[CoordinatorAgent-#{task.id}] Creating #{subtasks_to_create.count} subtasks..."
          subtasks_to_create.each do |subtask_data|
            execute_tool(:create_subtask, subtask_data[:title], subtask_data[:description], subtask_data[:priority])
          end
          # Optionally, immediately assign them (or let another run/logic handle assignment)
          task.reload # Reload to get newly created subtasks
          task.subtasks.where(state: "pending").each do |new_subtask|
            # Basic assignment, could be more sophisticated based on analysis
            # Assuming ResearcherAgent is a sensible default if analysis didn't specify
            execute_tool(:assign_subtask, new_subtask.id, "ResearcherAgent")
          end
          result_message = "Analyzed task, created and assigned #{subtasks_to_create.count} subtasks."
        else
          Rails.logger.warn "[CoordinatorAgent-#{task.id}] Analysis did not yield any subtasks."
          # Potentially mark task as complete if analysis suggests no breakdown needed?
          result_message = "Analyzed task, but no subtasks were identified."
          execute_tool(:mark_task_complete, "Task analyzed, no subtasks needed.")
        end
      else
        # If subtasks exist, check their status
        Rails.logger.info "[CoordinatorAgent-#{task.id}] Checking status of existing subtasks..."
        status_report = execute_tool(:check_subtasks)
        result_message = status_report # Use the report as the result

        # Check if all subtasks are completed
        task.reload # Refresh task state
        if task.subtasks.all? { |s| s.state == "completed" } && task.may_complete?
          Rails.logger.info "[CoordinatorAgent-#{task.id}] All subtasks completed. Marking main task complete."
          completion_summary = "Coordinator completed task after all subtasks finished."
          complete_result = execute_tool(:mark_task_complete, completion_summary)
          result_message << "\n" << complete_result
        elsif task.subtasks.any? { |s| s.state == "failed" }
           Rails.logger.warn "[CoordinatorAgent-#{task.id}] One or more subtasks have failed. Requires intervention or retry logic."
           # TODO: Implement retry/failure handling logic, maybe escalate?
           result_message << "\nWarning: Some subtasks failed."
        end
      end

    rescue => e
      # Handle errors during the run logic itself
      handle_run_error(e)
      raise # Re-raise error after logging/cleanup
    end

    # Final state setting before finishing
    @session_data[:output] = result_message
    after_run(result_message)
    result_message
  end
  # --- End Core Logic ---

  # --- Lifecycle Hooks ---
  # Override after_run for coordinator-specific logic (this might be redundant now)
  def after_run(result)
    super # Call base class after_run (updates status, persists tool execs)

    # The logic previously here (checking subtask completion) is now
    # integrated into the main `run` method for better control flow.
    # We can keep this method minimal or add other finalization steps if needed.
  end
  # --- End Lifecycle Hooks ---

  # --- Private Helpers ---
  private

  # Parses LLM output from analyze_task into an array of hashes
  # with :title, :description, :priority
  def parse_subtasks_from_llm(llm_output)
    # Example parse logic -- adapt to your LLM's actual output format
    # This example uses regex, assuming a format like:
    # Subtask 1: Title Text
    # Description: Description Text
    # Priority: Priority Text
    subtasks = []
    llm_output.scan(/Subtask\s*\d+:\s*(.*?)\nDescription:\s*(.*?)\nPriority:\s*(.*?)(?=\n\n|\z)/m) do |title, desc, priority|
      subtasks << {
        title: title.strip,
        description: desc.strip,
        priority: priority.strip.downcase
      }
    end
    subtasks
  rescue => e
     Rails.logger.error "[CoordinatorAgent] Failed to parse subtasks from LLM output: #{e.message}"
     [] # Return empty array on parsing failure
  end
  # --- End Private Helpers ---
end
