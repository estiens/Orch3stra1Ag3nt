# CoordinatorAgent: Strategically decomposes tasks and manages execution flow
class CoordinatorAgent < BaseAgent
  include EventSubscriber

  # Define a higher-priority queue
  def self.queue_name
    :coordinator
  end

  # Limit concurrency to prevent resource contention
  def self.concurrency_limit
    3
  end

  # Subscribe to relevant events for real-time coordination
  subscribe_to "subtask_completed", :handle_subtask_completed
  subscribe_to "subtask_failed", :handle_subtask_failed
  subscribe_to "task_waiting_on_human", :handle_human_input_required
  subscribe_to "tool_execution_finished", :handle_tool_execution
  subscribe_to "agent_completed", :handle_agent_completed
  subscribe_to "human_input_provided", :handle_human_input_provided

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

    Rails.logger.info "[CoordinatorAgent #{agent_activity&.id}] Subtask #{subtask_id} completed. Evaluating next steps."

    # Initiate a new coordinator run to evaluate progress and determine next actions
    self.class.enqueue(
      "Evaluate progress after subtask #{subtask_id} (#{subtask.title}) completed",
      {
        task_id: task.id,
        agent_activity_id: agent_activity.id,
        context: {
          event_type: "subtask_completed",
          subtask_id: subtask_id,
          result: event.data["result"]
        }
      }
    )
  end

  # Handle subtask failed event with recovery options
  def handle_subtask_failed(event)
    subtask_id = event.data["subtask_id"]
    return if subtask_id.blank?

    subtask = Task.find_by(id: subtask_id)
    return unless subtask

    parent_task = subtask.parent
    return unless parent_task && task && parent_task.id == task.id

    error = event.data["error"] || "Unknown error"
    Rails.logger.error "[CoordinatorAgent #{agent_activity&.id}] Subtask #{subtask_id} failed: #{error}"

    # Initiate a new coordinator run specifically to handle the failure
    self.class.enqueue(
      "Handle failure of subtask #{subtask_id} (#{subtask.title}): #{error}",
      {
        task_id: task.id,
        agent_activity_id: agent_activity.id,
        context: {
          event_type: "subtask_failed",
          subtask_id: subtask_id,
          error: error
        }
      }
    )
  end

  # Handle human input required
  def handle_human_input_required(event)
    task_id = event.data["task_id"]
    return if task_id.blank? || task&.id != task_id # Ensure event is for *this* coordinator's task

    question = event.data["question"]
    Rails.logger.warn "[CoordinatorAgent #{agent_activity&.id}] Human input required: #{question}"

    # Initiate a new coordinator run to assess alternatives while waiting for human input
    self.class.enqueue(
      "Assess alternatives while waiting for human input on task #{task_id}",
      {
        task_id: task.id,
        agent_activity_id: agent_activity.id,
        context: {
          event_type: "human_input_required",
          question: question
        }
      }
    )
  end

  # Handle tool execution finished event
  def handle_tool_execution(event)
    begin
      # Extract relevant data from the event
      tool_name = event.data["tool"]
      result_preview = event.data["result_preview"]

      # Only process events for this agent's activity
      return unless event.agent_activity_id == agent_activity&.id

      # Log the tool execution
      Rails.logger.info "[CoordinatorAgent #{agent_activity&.id}] Tool execution completed: #{tool_name}"

      # Handle specific tool completions if needed
      case tool_name
      when "create_subtask"
        # Check for errors in subtask creation
        if result_preview.to_s.include?("Error")
          Rails.logger.error "[CoordinatorAgent #{agent_activity&.id}] Subtask creation failed: #{result_preview}"
          # Potentially try to recover or notify about the error
        end
      when "assign_subtask"
        # Handle subtask assignment completion
        if result_preview.to_s.include?("Error") || result_preview.to_s.include?("Warning")
          Rails.logger.warn "[CoordinatorAgent #{agent_activity&.id}] Subtask assignment issue: #{result_preview}"
        end
      end
    rescue => e
      # Safely handle any errors during event processing
      Rails.logger.error "[CoordinatorAgent] Error handling tool execution event: #{e.message}"
    end
  end

  # Handle agent completed event
  def handle_agent_completed(event)
    begin
      # Extract relevant data
      result = event.data["result"]
      agent_activity_id = event.agent_activity_id

      return unless agent_activity_id

      # Look up the completed activity
      agent_activity = AgentActivity.find_by(id: agent_activity_id)
      return unless agent_activity

      # Get the associated task
      completed_task = agent_activity.task
      return unless completed_task

      # Get the parent task (which this coordinator is handling)
      parent_task_id = completed_task.parent_id
      return unless parent_task_id && parent_task_id == task&.id

      Rails.logger.info "[CoordinatorAgent #{agent_activity&.id}] Subtask #{completed_task.id} completed via agent activity #{agent_activity_id}"

      # Process as a subtask completed event
      # Reuse the subtask_completed handler logic
      subtask_completed_event = Event.create!(
        agent_activity_id: agent_activity&.id,
        event_type: "subtask_completed",
        data: {
          subtask_id: completed_task.id,
          result: result || "Task completed successfully"
        }
      )

      handle_subtask_completed(subtask_completed_event)
    rescue => e
      Rails.logger.error "[CoordinatorAgent] Error handling agent_completed event: #{e.message}"
    end
  end

  # Handle human input provided event
  def handle_human_input_provided(event)
    begin
      # Extract data from the event
      request_id = event.data["request_id"]
      input_task_id = event.data["task_id"]
      response = event.data["response"]

      # Skip if this doesn't relate to our task
      return unless task && input_task_id == task.id

      Rails.logger.info "[CoordinatorAgent #{agent_activity&.id}] Human input provided for task #{task.id}: #{response&.truncate(100)}"

      # Reload task to get current state
      task.reload

      # If task is waiting on human input, try to activate it
      if task.waiting_on_human? && task.may_activate?
        task.activate!
        update_task_status("Resuming task after human input: #{response&.truncate(50)}")

        # Start a new coordinator run to continue processing
        self.class.enqueue(
          "Resume after human input provided",
          {
            task_id: task.id,
            agent_activity_id: agent_activity&.id,
            context: {
              event_type: "task_resumed",
              input_request_id: request_id,
              response: response
            }
          }
        )
      end
    rescue => e
      Rails.logger.error "[CoordinatorAgent] Error handling human input provided: #{e.message}"
    end
  end
  # --- End Event Handlers ---

  # --- Tool Implementations ---
  def analyze_task(task_description)
    prompt_content = <<~PROMPT
      # STRATEGIC TASK ANALYSIS

      As an expert project manager, analyze and decompose the following task into a strategic plan of subtasks:

      ## TASK DESCRIPTION
      #{task_description}

      ## REQUIREMENTS
      1. Break this down into 3-7 DISTINCT subtasks (no overlap)
      2. Each subtask should have a SINGLE clear focus and objective
      3. Arrange subtasks in logical execution order (dependencies first)
      4. Consider what specialized agent types are needed for each subtask

      ## OUTPUT FORMAT
      For each subtask, provide:

      Subtask #{rand(1..100)}: {CLEAR, SPECIFIC TITLE}
      Description: {DETAILED instructions with success criteria}
      Priority: {high|normal|low}
      Agent: {ResearcherAgent|WebResearcherAgent|CodeResearcherAgent|WriterAgent|etc.}
      Dependencies: {List subtask numbers this depends on, or "None"}

      ## SPECIALIZED AGENT TYPES
      - ResearcherAgent: General information gathering and analysis
      - WebResearcherAgent: Internet searches and web information retrieval
      - CodeResearcherAgent: Code analysis, generation, and explanation, can run multiple in parallel analyzing different parts of a codebase
      - WriterAgent: Content creation, editing, and formatting
      - AnalyzerAgent: Data analysis and insight generation

      Create a comprehensive plan that when executed will FULLY accomplish the original task.
    PROMPT

    begin
      response = @llm.chat(messages: [ { role: "user", content: prompt_content } ])
      log_direct_llm_call(prompt_content, response)
      response.chat_completion
    rescue => e
      Rails.logger.error "[CoordinatorAgent] Error during task analysis: #{e.message}"
      "Error analyzing task: #{e.message}"
    end
  end

  def create_subtask(title, description, priority = "normal")
    unless task
      return "Error: Cannot create subtask - Coordinator not associated with a main task."
    end

    begin
      # Validate priority
      normalized_priority = priority.to_s.downcase
      unless [ "high", "normal", "low" ].include?(normalized_priority)
        normalized_priority = "normal"
      end

      # Create a new agent activity for the subtask
      subtask_agent_activity = AgentActivity.create!(
        task: task,
        agent_type: "coordinator_agent",
        status: "pending",
        parent_id: agent_activity&.id,
        metadata: { purpose: "Subtask: #{title}" }
      )

      subtask = task.subtasks.create!(
        title: title,
        description: description,
        priority: normalized_priority,
        state: "pending", # Initial state
        metadata: { created_by: "coordinator_agent" }
      )

      # Create the required agent activity for the subtask
      subtask_agent_activity.update!(task: subtask)

      agent_activity&.events.create!(
        event_type: "subtask_created",
        data: { subtask_id: subtask.id, parent_id: task.id, title: title, priority: normalized_priority }
      )

      Event.publish(
        "subtask_created",
        { subtask_id: subtask.id, parent_id: task.id, title: title, priority: normalized_priority },
        { agent_activity_id: agent_activity&.id }
      )

      "Created subtask '#{title}' (ID: #{subtask.id}, Priority: #{normalized_priority}) for task #{task.id}"
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

      meaningful_purpose = purpose.presence || "Execute subtask: #{subtask.title}"

      agent_options = {
        task_id: subtask.id,
        parent_activity_id: agent_activity&.id,
        purpose: meaningful_purpose,
        task_priority: subtask.priority,
        metadata: {
          coordinator_id: agent_activity&.id,
          parent_task_id: task.id
        }
      }

      # Use the agent class's enqueue method
      job = agent_class.enqueue(
        "#{subtask.title}\n\n#{subtask.description}",
        agent_options
      )

      if job
        subtask.activate! if subtask.may_activate? # Transition state

        subtask.update(
          metadata: (subtask.metadata || {}).merge({
            assigned_agent: agent_class_name,
            assigned_at: Time.current
          })
        )

        agent_activity&.events.create!(
          event_type: "subtask_assigned",
          data: { subtask_id: subtask.id, agent_type: agent_class_name, purpose: meaningful_purpose }
        )

        "Assigned subtask #{subtask_id} ('#{subtask.title}') to #{agent_class_name} with purpose: '#{meaningful_purpose}'."
      else
        "Warning: Subtask #{subtask_id} could not be assigned to #{agent_class_name} due to concurrency limits. It remains in '#{subtask.state}' state."
      end
    rescue NameError => e
      "Error: Agent type '#{agent_class_name}' not found. Available types: ResearcherAgent, WebResearcherAgent, CodeResearcherAgent, WriterAgent, AnalyzerAgent."
    rescue => e
      Rails.logger.error "[CoordinatorAgent] Error assigning subtask #{subtask_id}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      "Error assigning subtask #{subtask_id}: #{e.message}"
    end
  end

  def check_subtasks
    unless task
      return "Error: Cannot check subtasks - Coordinator not associated with a main task."
    end

    task.reload
    subtasks = task.subtasks.order(:created_at)

    if subtasks.empty?
      return "No subtasks found for task #{task.id}: '#{task.title}'."
    end

    # Generate statistics
    total = subtasks.count
    by_state = subtasks.group_by(&:state)
    by_priority = subtasks.group_by(&:priority)

    # Create detailed report
    report = <<~REPORT
      # SUBTASK STATUS REPORT

      ## Task: #{task.title} (ID: #{task.id})

      ### Summary Statistics
      - Total Subtasks: #{total}
      - Completed: #{by_state['completed']&.count || 0} (#{((by_state['completed']&.count || 0) * 100.0 / total).round}%)
      - In Progress: #{by_state['active']&.count || 0}
      - Pending: #{by_state['pending']&.count || 0}
      - Failed: #{by_state['failed']&.count || 0}
      - Other States: #{subtasks.count - (by_state['completed']&.count || 0) - (by_state['active']&.count || 0) - (by_state['pending']&.count || 0) - (by_state['failed']&.count || 0)}

      ### By Priority
      - High: #{by_priority['high']&.count || 0}
      - Normal: #{by_priority['normal']&.count || 0}
      - Low: #{by_priority['low']&.count || 0}

      ### Detailed Status
    REPORT

    # Add detailed subtask information
    subtasks.each do |st|
      agent_type = st.metadata&.dig("assigned_agent") || "Not assigned"
      created_at = st.created_at&.strftime("%Y-%m-%d %H:%M")
      status_icon = case st.state
      when "completed" then "✅"
      when "active" then "🔄"
      when "pending" then "⏳"
      when "failed" then "❌"
      when "waiting_on_human" then "👤"
      else "❓"
      end

      report += "#{status_icon} [ID #{st.id}][#{st.priority.upcase}] #{st.title} (#{agent_type}, created #{created_at})\n"
    end

    # Add recommendations based on status
    report += "\n### Recommendations\n"

    if by_state["failed"]&.any?
      report += "- URGENT: #{by_state['failed'].count} subtasks have failed and need attention.\n"
    end

    if by_state["pending"]&.any?
      report += "- #{by_state['pending'].count} subtasks are pending assignment.\n"
    end

    if by_state["completed"]&.count == total
      report += "- All subtasks are complete! Use mark_task_complete to finalize the task.\n"
    else
      completion_percentage = ((by_state["completed"]&.count || 0) * 100.0 / total).round
      report += "- Overall progress: #{completion_percentage}% complete.\n"
    end

    report
  end

  def update_task_status(status_message)
    unless task
      return "Error: Cannot update status - Coordinator not associated with a main task."
    end

    begin
      timestamp = Time.current.strftime("%Y-%m-%d %H:%M")
      # Append notes or replace? Let's append for now.
      new_notes = "#{task.notes}\n[#{timestamp} Coordinator Update]: #{status_message}".strip
      task.update!(notes: new_notes)

      agent_activity&.events.create!(
        event_type: "status_update",
        data: { task_id: task.id, message: status_message, timestamp: timestamp }
      )

      "✓ Task #{task.id} status updated: '#{status_message}'"
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
        status_msg = "❗ Task #{task.id} is now BLOCKED waiting for required human input"
      else
        status_msg = "👤 Optional human input requested for task #{task.id} (will continue processing)"
      end

      Event.publish(
        "human_input_requested",
        { request_id: input_request.id, task_id: task.id, question: question, required: required },
        {
          agent_activity_id: agent_activity&.id,
          priority: required ? Event::HIGH_PRIORITY : Event::NORMAL_PRIORITY
        }
      )

      "#{status_msg}: '#{question}' (Request ID: #{input_request.id})"
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
      subtask_details = incomplete_subtasks.map { |st| "#{st.id} (#{st.title}: #{st.state})" }.join(", ")
      return "⚠️ Cannot complete task #{task.id} - #{incomplete_subtasks.count} subtasks are incomplete: #{subtask_details}"
    end

    begin
      # Generate a comprehensive summary if none provided
      if summary.blank? && task.subtasks.any?
        summary = generate_completion_summary(task)
      end

      # Update with final summary
      task.update!(result: summary) if summary.present?

      if task.may_complete?
        task.complete!

        Event.publish(
          "task_completed",
          { task_id: task.id, result: summary },
          { agent_activity_id: agent_activity&.id }
        )

        "✅ Task #{task.id} ('#{task.title}') successfully COMPLETED!"
      else
        "⚠️ Task #{task.id} cannot be completed from its current state: '#{task.state}'"
      end
    rescue => e
      Rails.logger.error "[CoordinatorAgent] Error marking task complete: #{e.message}"
      "Error marking task #{task.id} complete: #{e.message}"
    end
  end

  # Generate a comprehensive task summary from subtask results
  def generate_completion_summary(task)
    subtasks = task.subtasks.where(state: "completed")

    if subtasks.empty?
      return "Task completed without subtasks."
    end

    # Create a prompt for summarizing the results
    subtask_results = subtasks.map do |st|
      "## Subtask: #{st.title}\n#{st.result}"
    end.join("\n\n---\n\n")

    prompt = <<~PROMPT
      # TASK COMPLETION SUMMARY

      Generate a comprehensive, well-organized summary of this completed task based on the results of all subtasks.

      ## ORIGINAL TASK
      #{task.title}
      #{task.description}

      ## SUBTASK RESULTS
      #{subtask_results}

      ## REQUIRED OUTPUT FORMAT
      Create an executive summary that:
      1. Provides a high-level overview of what was accomplished
      2. Synthesizes the key findings/results from all subtasks
      3. Organizes information logically with clear section headings
      4. Highlights any important insights or recommendations
      5. Uses professional, concise language appropriate for a final report

      Your summary should be comprehensive but focused on the most relevant information.
    PROMPT

    begin
      response = @llm.chat(messages: [ { role: "user", content: prompt } ])
      log_direct_llm_call(prompt, response)
      response.chat_completion
    rescue => e
      Rails.logger.error "[CoordinatorAgent] Error generating completion summary: #{e.message}"
      "Task completed successfully. Error generating detailed summary: #{e.message}"
    end
  end
  # --- End Tool Implementations ---

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
      elsif task.reload.subtasks.empty? # Check if subtasks are *actually* empty
        # Initial decomposition for new tasks
        result_message = perform_initial_task_decomposition
      else
        # General progress check and next steps
        result_message = evaluate_current_progress
      end

    rescue => e
      handle_run_error(e)
      raise
    end

    @session_data[:output] = result_message
    after_run(result_message) # This run finishes, event handlers will trigger next run if needed
    result_message
  end

  # Handle a failed subtask with recovery options
  def handle_failed_subtask(subtask_id, error)
    subtask = task.subtasks.find_by(id: subtask_id)
    return "Error: Failed subtask #{subtask_id} not found" unless subtask

    Rails.logger.info "[CoordinatorAgent-#{task.id}] Handling failed subtask #{subtask_id}: #{subtask.title}"

    # Log the failure
    update_task_status("Subtask #{subtask_id} (#{subtask.title}) failed: #{error}")

    # Analyze failure using LLM to determine recovery strategy
    prompt = <<~PROMPT
      # SUBTASK FAILURE ANALYSIS

      A subtask has failed and requires intelligent handling. Analyze the failure and recommend ONE of the following actions:
      1. RETRY - The subtask can be attempted again with the same parameters
      2. REDEFINE - The subtask needs to be redefined with different parameters
      3. SPLIT - The subtask should be split into smaller, more manageable subtasks
      4. HUMAN - Human intervention is required to proceed
      5. SKIP - The subtask can be skipped without affecting the overall task

      ## FAILED SUBTASK
      ID: #{subtask_id}
      Title: #{subtask.title}
      Description: #{subtask.description}
      Assigned Agent: #{subtask.metadata&.dig("assigned_agent") || "Unknown"}

      ## ERROR DETAILS
      #{error}

      ## PARENT TASK CONTEXT
      Task: #{task.title}
      Description: #{task.description}

      ## RECOMMENDATION FORMAT
      ACTION: [ONE of: RETRY, REDEFINE, SPLIT, HUMAN, SKIP]
      REASON: [Brief explanation of your recommendation]
      DETAILS: [Any specific details needed to implement your recommendation]
    PROMPT

    begin
      response = @llm.chat(messages: [ { role: "user", content: prompt } ])
      log_direct_llm_call(prompt, response)
      analysis = response.chat_completion

      # Parse LLM response to get recommended action
      if analysis.include?("ACTION: RETRY")
        # Attempt to reassign the same subtask
        subtask.update(state: "pending")
        assign_subtask(subtask_id, subtask.metadata&.dig("assigned_agent") || "ResearcherAgent", "Retry after failure: #{error}")
      elsif analysis.include?("ACTION: REDEFINE")
        # Create a new improved version of the subtask
        description = "REDEFINED AFTER FAILURE: #{subtask.description}\n\nPrevious Error: #{error}"
        new_subtask = create_subtask("Redefined: #{subtask.title}", description, subtask.priority)
        # Extract subtask ID from result
        new_id = new_subtask.match(/ID: (\d+)/)[1] rescue nil
        if new_id
          assign_subtask(new_id, subtask.metadata&.dig("assigned_agent") || "ResearcherAgent", "Redefined after failure")
        else
          "Created redefined subtask, but failed to extract ID for assignment: #{new_subtask}"
        end
      elsif analysis.include?("ACTION: SPLIT")
        # Request a decomposition of the failed subtask
        "Initiating decomposition of failed subtask. Marking original as canceled."
      elsif analysis.include?("ACTION: HUMAN")
        # Request human intervention
        request_human_input("Subtask #{subtask_id} (#{subtask.title}) failed and requires human intervention: #{error}", true)
      elsif analysis.include?("ACTION: SKIP")
        # Mark as successful with explanation
        subtask.update(state: "completed", result: "Skipped due to non-critical failure: #{error}")
        "Marked subtask #{subtask_id} as completed (skipped) as it was deemed non-critical."
      else
        # Default to human intervention if analysis is unclear
        request_human_input("Subtask #{subtask_id} failed and automatic recovery is unclear. Please review: #{error}", false)
      end
    rescue => e
      Rails.logger.error "[CoordinatorAgent] Error analyzing failed subtask: #{e.message}"
      request_human_input("Error analyzing failed subtask #{subtask_id}: #{e.message}. Original error: #{error}", true)
    end
  end

  # Process a completed subtask and determine next steps
  def process_completed_subtask(subtask_id, result)
    task.reload

    # Log completion
    update_task_status("Subtask #{subtask_id} completed successfully.")

    # Check overall task progress
    status_report = check_subtasks

    # If all subtasks are complete, finalize the task
    if task.subtasks.all? { |s| s.state == "completed" }
      return mark_task_complete # This will generate the final summary
    end

    # Find and assign the next *eligible* subtask
    eligible_subtasks = find_eligible_pending_subtasks
    if eligible_subtasks.any?
      # Assign the highest priority eligible subtask
      next_subtask = select_next_subtask_to_assign(eligible_subtasks)
      agent_type = next_subtask.metadata&.dig("suggested_agent") || determine_best_agent_for_subtask(next_subtask)
      assign_result = assign_subtask(next_subtask.id, agent_type, "Assigning next eligible subtask")
      return "#{status_report}\\n\\n#{assign_result}"
    end

    # Return comprehensive status if no immediate action needed
    active_count = task.subtasks.where(state: "active").count
    "#{status_report}\\n\\nContinuing to monitor #{active_count} active subtasks. No new subtasks are eligible for assignment yet."
  end

  # Handle human input requirement
  def handle_human_input_requirement(question)
    task.reload

    # Check if there are eligible pending subtasks that can proceed in parallel
    eligible_subtasks = find_eligible_pending_subtasks

    if eligible_subtasks.any?
      # We can still make progress on other subtasks while waiting
      status = "Working on parallel subtasks while waiting for human input: '#{question}'"
      update_task_status(status)

      # Find and assign an eligible subtask we can work on
      next_subtask = select_next_subtask_to_assign(eligible_subtasks)
      agent_type = next_subtask.metadata&.dig("suggested_agent") || determine_best_agent_for_subtask(next_subtask)
      assign_result = assign_subtask(next_subtask.id, agent_type, "Parallel work while waiting for human input")

      "#{status}\\n\\n#{assign_result}"
    else
      # Nothing else to do but wait
      active_count = task.subtasks.where(state: "active").count
      "Task is waiting for human input on question: '#{question}'. #{active_count} subtasks still active. No parallel work available."
    end
  end

  # Perform initial task decomposition
  def perform_initial_task_decomposition
    Rails.logger.info "[CoordinatorAgent-#{task.id}] Performing initial task decomposition for: #{task.title}"

    # Analyze the task
    analysis_result = execute_tool(:analyze_task, task_description: task.description)

    # Parse subtasks from the analysis, including dependency indices
    subtasks_data = parse_subtasks_from_llm(analysis_result) # Ensure this returns dependency indices

    if subtasks_data.empty?
      Rails.logger.warn "[CoordinatorAgent-#{task.id}] Analysis did not yield any subtasks."
      return "Task analysis complete, but no subtasks were identified. This may indicate the task is too simple for decomposition or the analysis failed."
    end

    # Record the decomposition strategy
    update_task_status("Task decomposed into #{subtasks_data.count} subtasks: #{subtasks_data.map { |s| s[:title] }.join(', ')}")

    # --- Create all subtasks first ---
    created_subtasks_map = {} # Map original index to created subtask object
    subtasks_data.each_with_index do |subtask_info, index|
      # Create subtask but don't assign yet
      create_result = execute_tool(:create_subtask,
                           title: subtask_info[:title],
                           description: subtask_info[:description],
                           priority: subtask_info[:priority])
      # Extract ID (assuming result format is like "Created subtask '...' (ID: 123, ...)")
      subtask_id = create_result.match(/ID: (\d+)/)&.[](1)&.to_i
      if subtask_id
        subtask = Task.find(subtask_id)
        # Store suggested agent type and original index in metadata for later use
        subtask.update!(metadata: subtask.metadata.merge({
          suggested_agent: subtask_info[:agent_type],
          original_index: index + 1
        }))
        created_subtasks_map[index + 1] = subtask # Map original index to subtask
      else
        Rails.logger.error "[CoordinatorAgent-#{task.id}] Failed to extract subtask ID from create result: #{create_result}"
        # Handle error - maybe request human input?
        request_human_input("Failed to create or parse subtask '#{subtask_info[:title]}'. Please review decomposition.", true)
        return "Error during subtask creation. Human input requested."
      end
    end

    # --- Now update dependencies ---
    created_subtasks_map.each do |original_index, subtask|
      # Find original dependency indices for this subtask
      dependency_indices = subtasks_data[original_index - 1][:dependencies] # Get indices from original data

      # Map indices to actual Task IDs
      dependency_ids = dependency_indices.map { |idx| created_subtasks_map[idx]&.id }.compact

      # Update the subtask record
      subtask.update!(depends_on_task_ids: dependency_ids) unless dependency_ids.empty?
    end

    # --- Assign initially eligible subtasks ---
    eligible_subtasks = find_eligible_pending_subtasks
    assigned_count = 0
    if eligible_subtasks.any?
      # Assign potentially multiple initially eligible tasks (those with no deps)
      eligible_subtasks.each do |subtask_to_assign|
         agent_type = subtask_to_assign.metadata&.dig("suggested_agent") || determine_best_agent_for_subtask(subtask_to_assign)
         assign_subtask(subtask_to_assign.id, agent_type, "Assigning initial eligible subtask")
         assigned_count += 1
      end
      "Task successfully decomposed into #{subtasks_data.count} subtasks. " +
      "#{assigned_count} initially eligible subtasks have been assigned. " +
      "Remaining subtasks will be assigned as dependencies are satisfied."
    else
      "Task successfully decomposed into #{subtasks_data.count} subtasks. " +
      "No subtasks are immediately eligible for assignment (check dependencies)."
    end
  end

  # Evaluate current task progress and determine next actions
  def evaluate_current_progress
    task.reload

    # Get comprehensive status report
    status_report = check_subtasks

    # Check if task is already completed
    if task.state == "completed"
      return "Task #{task.id} is already completed."
    end

    # Check if all subtasks are completed but task isn't marked complete
    if task.subtasks.any? && task.subtasks.all? { |s| s.state == "completed" }
      completion_result = mark_task_complete
      return "#{status_report}\\n\\n#{completion_result}"
    end

    # Check for failed subtasks (should trigger handle_failed_subtask via events, but double-check)
    failed_subtasks = task.subtasks.where(state: "failed")
    if failed_subtasks.any?
      failed_ids = failed_subtasks.pluck(:id).join(", ")
      # Consider triggering failure handling if event missed?
      return "#{status_report}\\n\\nATTENTION REQUIRED: Found #{failed_subtasks.count} failed subtasks: #{failed_ids}. Failure handling should be initiated via events."
    end

    # Check for eligible pending subtasks that can be assigned
    eligible_subtasks = find_eligible_pending_subtasks
    if eligible_subtasks.any?
      # Assign the highest priority eligible subtask
      next_subtask = select_next_subtask_to_assign(eligible_subtasks)
      agent_type = next_subtask.metadata&.dig("suggested_agent") || determine_best_agent_for_subtask(next_subtask)
      assign_result = assign_subtask(next_subtask.id, agent_type, "Assigning next eligible subtask during progress check")

      return "#{status_report}\\n\\n#{assign_result}"
    end

    # Default: just report status if no immediate action needed
    active_count = task.subtasks.where(state: "active").count
    pending_count = task.subtasks.where(state: "pending").count
    "#{status_report}\\n\\nTask is progressing with #{active_count} active subtasks and #{pending_count} pending (waiting on dependencies). No new subtasks are eligible for assignment yet."
  end
  # --- End Core Logic ---

  # --- Private Helpers ---
  private

  # Parses LLM output to extract structured subtask information
  # MODIFIED to return dependency indices
  def parse_subtasks_from_llm(llm_output)
    subtasks = []

    # Split by common subtask separator patterns
    sections = llm_output.split(/---|\*{3}|={3}|Subtask\s+\d+:/).reject(&:empty?)

    # If we don't find sections with the splitter, try another approach
    if sections.size <= 1
      # Try parsing with the numbered subtask format
      sections = llm_output.scan(/Subtask\s+\d+:.*?(?=Subtask\s+\d+:|$)/m)
    end

    # Process each section
    sections.each do |section|
      # Extract basic components with less complex patterns
      title_match = section.match(/(?:Subtask\s+\d+:)?\s*(.*?)(?:\r?\n|\n|$)/)
      description_match = section.match(/Description:?\s*(.*?)(?:Priority:|Agent:|Dependencies:|$)/m)
      priority_match = section.match(/Priority:?\s*([Hh]igh|[Nn]ormal|[Ll]ow)/)
      agent_match = section.match(/Agent:?\s*([A-Za-z]+Agent)/)
      deps_match = section.match(/Dependencies:?\s*(None|(?:\d+(?:,\s*\d+)*))/)

      # Skip if we can't extract the minimum required information
      next unless title_match && description_match && priority_match

      title = title_match[1].strip
      description = description_match[1].strip
      priority = priority_match[1].downcase.strip
      agent_type = agent_match ? agent_match[1].strip : "ResearcherAgent"

      # Parse dependencies
      deps_str = deps_match ? deps_match[1].strip : "None"
      dependency_indices = deps_str.downcase == "none" ? [] : deps_str.split(/,\s*/).map(&:to_i)

      # Don't add if title is empty or just whitespace
      next if title.empty?

      subtasks << {
        title: title,
        description: description,
        priority: priority,
        agent_type: agent_type,
        dependencies: dependency_indices
      }
    end

    Rails.logger.info "[CoordinatorAgent] Parsed #{subtasks.count} subtasks from analysis"

    # Return early if we found subtasks
    return subtasks unless subtasks.empty?

    # Last resort: try a very simple pattern matching approach for each subtask
    begin
      # Look for potential subtask titles
      potential_titles = llm_output.scan(/(?:^|\n)(?:Subtask\s+\d+:)?\s*([A-Z][\w\s,]+)(?:\n|$)/)

      potential_titles.each_with_index do |title_match, index|
        title = title_match[0].strip
        # Get the section following this title (until the next potential title or end)
        next_title_pos = llm_output.index(potential_titles[index + 1]&.[](0)) if index + 1 < potential_titles.size
        section = next_title_pos ? llm_output[llm_output.index(title)...next_title_pos] : llm_output[llm_output.index(title)..-1]

        # Try to extract description and priority
        desc_text = section.match(/(?:Description:?\s*)(.*?)(?:Priority:|Agent:|Dependencies:|$)/m)&.[](1)&.strip
        priority_text = section.match(/Priority:?\s*([Hh]igh|[Nn]ormal|[Ll]ow)/)&.[](1)&.downcase

        next unless desc_text && priority_text

        subtasks << {
          title: title,
          description: desc_text,
          priority: priority_text,
          agent_type: "ResearcherAgent", # Default
          dependencies: []  # Default empty
        }
      end
    rescue => parsing_error
      Rails.logger.error "[CoordinatorAgent] Error in fallback parsing: #{parsing_error.message}"
    end

    Rails.logger.info "[CoordinatorAgent] Final parsed subtask count: #{subtasks.count}"
    subtasks
  rescue => e
    Rails.logger.error "[CoordinatorAgent] Failed to parse subtasks: #{e.message}"
    Rails.logger.error "LLM Output (first 500 chars): #{llm_output[0..500]}"
    []
  end

  # NEW: Find pending subtasks whose dependencies are met
  def find_eligible_pending_subtasks
    pending_subtasks = task.subtasks.where(state: "pending")
    return [] if pending_subtasks.empty?

    # Check if dependencies are satisfied using the method we added to Task
    pending_subtasks.select(&:dependencies_satisfied?)
  end

  # NEW: Select the next subtask to assign from a list of eligible ones
  def select_next_subtask_to_assign(eligible_subtasks)
    # Prioritize by 'priority' field (high > normal > low), then by creation date (oldest first)
    priority_order = { "high" => 0, "normal" => 1, "low" => 2 }
    eligible_subtasks.min_by { |s| [ priority_order[s.priority] || 99, s.created_at.to_i ] }
  end

  # Determine the best agent type for a subtask (fallback if not suggested)
  def determine_best_agent_for_subtask(subtask)
    # First check if the subtask already has a predetermined agent type
    if subtask.metadata&.dig("agent_type")
      return subtask.metadata["agent_type"]
    end

    # Use stored agent recommendation from task decomposition if available
    # This requires storing the recommendation during parse_subtasks_from_llm

    # Otherwise, analyze the subtask description to suggest an appropriate agent
    prompt = <<~PROMPT
      # AGENT SELECTION

      Based on this subtask description, determine the SINGLE most appropriate agent type:

      ## SUBTASK
      Title: #{subtask.title}
      Description: #{subtask.description}

      ## AVAILABLE AGENT TYPES
      - ResearcherAgent: General research and information gathering
      - WebResearcherAgent: Web browsing and internet research
      - CodeResearcherAgent: Code analysis and programming tasks
      - WriterAgent: Content creation and documentation
      - AnalyzerAgent: Data analysis and insight generation

      ## REQUIRED OUTPUT FORMAT
      RECOMMENDED AGENT: [Single agent type from the list above]
      REASON: [Brief justification]
    PROMPT

    begin
      response = @llm.chat(messages: [ { role: "user", content: prompt } ])
      log_direct_llm_call(prompt, response)
      analysis = response.chat_completion
      if analysis =~ /RECOMMENDED AGENT:\s*([A-Za-z]+Agent)/
        $1
      else
        "ResearcherAgent"
      end
    rescue => e
      Rails.logger.error "[CoordinatorAgent] Error determining agent type: #{e.message}"
      "ResearcherAgent" # Safe fallback
    end
  end

  # --- End Private Helpers ---
end
