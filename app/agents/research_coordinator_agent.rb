# ResearchCoordinatorAgent: Specialized coordinator for research tasks
# Manages the research process through multiple sub-agents
class ResearchCoordinatorAgent < BaseAgent
  include EventSubscriber

  # Define queue
  def self.queue_name
    :research_coordinator
  end

  # Limit concurrency to 2 research coordinators at a time
  def self.concurrency_limit
    2
  end

  # Subscribe to relevant events
  subscribe_to "research_task_created", :handle_new_research_task
  subscribe_to "research_subtask_completed", :handle_research_completed
  subscribe_to "research_subtask_failed", :handle_research_failed

  # --- Tools ---
  tool :analyze_research_question, "Break down a research question into specific research tasks" do |research_question|
    analyze_research_question(research_question)
  end

  tool :create_research_subtask, "Create a subtask for a specific research area" do |title, description, methods = nil|
    create_research_subtask(title, description, methods)
  end

  tool :assign_researcher, "Assign a research subtask to an appropriate researcher agent" do |subtask_id, methods = []|
    assign_researcher(subtask_id, methods)
  end

  tool :consolidate_findings, "Combine and synthesize research findings" do
    consolidate_findings
  end

  tool :check_existing_knowledge, "Check if we already have information on a topic in our database" do |query|
    # Placeholder - Requires Vector DB implementation
    check_existing_knowledge(query)
  end

  tool :store_research_finding, "Store a research finding in the vector database" do |finding, metadata = {}|
    # Placeholder - Requires Vector DB implementation
    store_research_finding(finding, metadata)
  end

  tool :request_human_guidance, "Request guidance from a human on research direction" do |question, context = nil|
    request_human_guidance(question, context)
  end
  # --- End Tools ---

  # --- Event Handlers ---
  # Handle new research task event - Typically triggered by Orchestrator
  def handle_new_research_task(event)
    task_id = event.data["task_id"]
    return if task_id.blank?

    # This handler might run in a separate instance context than the agent run.
    # Need to decide if it should trigger a *new* agent run or just log.
    begin
      research_task = Task.find(task_id)
      Rails.logger.info "[ResearchCoordinatorAgentEventHandler] Received handle_new_research_task for Task #{task_id}: #{research_task.title}."
      # Option 1: Trigger a new agent run (most likely needed to start the process)
      # Note: This assumes the event triggers a job that *instantiates* and runs the agent.
      # If the event handler is called on an existing instance, `self.run` might work differently.
      # ResearchCoordinatorAgent.enqueue(
      #   "Plan research for: #{research_task.title}",
      #   { task_id: task_id, purpose: "Plan and execute research for task #{task_id}" }
      # )
    rescue ActiveRecord::RecordNotFound
      Rails.logger.error "[ResearchCoordinatorAgentEventHandler] Task #{task_id} not found for handle_new_research_task."
    end
  end

  # Handle research completion event
  def handle_research_completed(event)
    subtask_id = event.data["subtask_id"]
    return if subtask_id.blank?

    begin
      subtask = Task.find(subtask_id)
      parent_task = subtask.parent
      return unless parent_task # Ensure it's a subtask

      # Check if this event is relevant to an *active* coordinator for this parent task
      # This logic might be complex depending on how coordinators are managed.
      # For now, just log globally.
      Rails.logger.info "[ResearchCoordinatorAgentEventHandler] Received handle_research_completed for Subtask #{subtask_id} (Parent: #{parent_task.id})."
      # An active coordinator for parent_task.id might trigger its run or call consolidate_findings tool.

    rescue ActiveRecord::RecordNotFound
       Rails.logger.error "[ResearchCoordinatorAgentEventHandler] Subtask #{subtask_id} not found for handle_research_completed."
    end
  end

  # Handle research failure event
  def handle_research_failed(event)
     subtask_id = event.data["subtask_id"]
     return if subtask_id.blank?

     begin
       subtask = Task.find(subtask_id)
       parent_task = subtask.parent
       return unless parent_task

       error = event.data["error"] || "Research failed with unknown error"
       Rails.logger.error "[ResearchCoordinatorAgentEventHandler] Received handle_research_failed for Subtask #{subtask_id} (Parent: #{parent_task.id}): #{error}"
       # An active coordinator for parent_task.id might trigger its run or try other actions.

     rescue ActiveRecord::RecordNotFound
        Rails.logger.error "[ResearchCoordinatorAgentEventHandler] Subtask #{subtask_id} not found for handle_research_failed."
     end
  end
  # --- End Event Handlers ---

  # --- Core Logic ---
  def run(input = nil) # Input likely the research question/topic
    before_run(input)

    unless task
      result = "ResearchCoordinatorAgent Error: Agent not associated with a task."
      Rails.logger.error result
      @session_data[:output] = result
      after_run(result)
      return result
    end

    result_message = "Research Coordinator run completed."
    begin
      if task.subtasks.empty?
        Rails.logger.info "[ResearchCoordinator-#{task.id}] Analyzing research question: #{task.title}"
        # Analyze the main research question
        analysis = execute_tool(:analyze_research_question, input || task.description)

        # TODO: Parse analysis to get subtask details (focus, methods, contribution)
        # Placeholder parsing - assumes analysis provides structured info
        subtasks_to_create = parse_research_subtasks(analysis)

        if subtasks_to_create.any?
          Rails.logger.info "[ResearchCoordinator-#{task.id}] Creating #{subtasks_to_create.count} research subtasks..."
          subtasks_to_create.each do |subtask_data|
             # Create subtask
             create_result = execute_tool(:create_research_subtask,
                                           subtask_data[:title],
                                           subtask_data[:description],
                                           subtask_data[:methods])
             # Extract subtask ID (assuming create_tool returns it like "... ID 123")
             subtask_id_match = create_result.match(/ID\s*(\d+)/)
             if subtask_id_match
                subtask_id = subtask_id_match[1].to_i
                # Assign researcher based on methods
                execute_tool(:assign_researcher, subtask_id, subtask_data[:methods])
             else
                Rails.logger.error "[ResearchCoordinator-#{task.id}] Could not extract subtask ID from create result: #{create_result}"
             end
          end
           result_message = "Analyzed research question, created and assigned #{subtasks_to_create.count} subtasks."
        else
          Rails.logger.warn "[ResearchCoordinator-#{task.id}] Analysis did not yield subtasks."
          result_message = "Analyzed research question, but no subtasks identified."
          # Might need to assign the main task directly? Or mark complete?
          # execute_tool(:assign_researcher, task.id, ["web"]) # Example: assign main task
        end
      else
        # If subtasks exist, check status and consolidate if needed
        Rails.logger.info "[ResearchCoordinator-#{task.id}] Checking research subtasks..."
        task.reload # Refresh subtask states
        completed_subtasks = task.subtasks.where(state: "completed")
        failed_subtasks = task.subtasks.where(state: "failed")
        active_subtasks = task.subtasks.where(state: "active")
        pending_subtasks = task.subtasks.where(state: "pending")

        if failed_subtasks.any?
           result_message = "One or more research subtasks failed. Needs review."
           # Optional: Escalate or trigger retry logic here
           Rails.logger.warn "[ResearchCoordinator-#{task.id}] Failed subtasks: #{failed_subtasks.pluck(:id).join(', ')}"
        elsif active_subtasks.any? || pending_subtasks.any?
           result_message = "Research in progress. Waiting on #{active_subtasks.count} active and #{pending_subtasks.count} pending subtasks."
           Rails.logger.info result_message
        elsif completed_subtasks.count == task.subtasks.count
           Rails.logger.info "[ResearchCoordinator-#{task.id}] All research subtasks completed. Consolidating findings..."
           consolidation_result = execute_tool(:consolidate_findings)
           # Mark the main task complete after consolidating
           task.complete! if task.may_complete?
           result_message = "Consolidated findings:\n#{consolidation_result}"
        else
           result_message = "Research status unclear. Subtasks: #{task.subtasks.count} total, #{completed_subtasks.count} completed."
        end
      end

    rescue => e
      handle_run_error(e)
      raise
    end

    @session_data[:output] = result_message
    after_run(result_message)
    result_message
  end
  # --- End Core Logic ---

  # --- Tool Implementations ---
  def analyze_research_question(research_question)
    prompt_content = <<~PROMPT
      Break down the following research question into specific, actionable research tasks:

      RESEARCH QUESTION: #{research_question}

      Provide 3-5 focused subtasks with:
      1. Research focus
      2. Suggested methods/sources
      3. Contribution to the overall question

      FORMAT:
      Research Task 1: [FOCUS]
      Methods: [METHODS/SOURCES]
      Contribution: [CONTRIBUTION]
      ...

      Finally, provide a brief research plan (order and rationale).
    PROMPT

    begin
      # Use the agent's LLM instance provided by BaseAgent
      response = @llm.chat(messages: [ { role: "user", content: prompt_content } ])

      # Manually log the LLM call
      log_direct_llm_call(prompt_content, response)

      response.chat_completion # Or response.content
    rescue => e
      Rails.logger.error "[ResearchCoordinatorAgent] LLM Error in analyze_research_question: #{e.message}"
      "Error analyzing research question: #{e.message}"
    end
  end

  def create_research_subtask(title, description, methods = nil)
    unless task
      return "Error: Cannot create research subtask - Coordinator not associated with a main task."
    end

    begin
      metadata = {}
      metadata[:research_methods] = Array(methods) if methods.present?

      subtask = task.subtasks.create!(
        title: title,
        description: description,
        priority: "normal",
        state: "pending",
        metadata: metadata
      )

      # Event logging within the agent activity is handled by callbacks if this is called via a tool
      # If called directly, manual logging might be needed, but tools are preferred.

      # Publish system-wide event
      Event.publish(
        "research_subtask_created",
        { subtask_id: subtask.id, parent_id: task.id, title: title, methods: methods }
      )

      "Created research subtask '#{title}' (ID: #{subtask.id}) for task #{task.id}"
    rescue => e
      Rails.logger.error "[ResearchCoordinatorAgent] Error creating research subtask: #{e.message}"
      "Error creating research subtask '#{title}': #{e.message}"
    end
  end

  def assign_researcher(subtask_id, methods = [])
     unless task
       return "Error: Cannot assign researcher - Coordinator not associated with a main task."
     end

     begin
       subtask = task.subtasks.find(subtask_id)
     rescue ActiveRecord::RecordNotFound
       return "Error: Subtask #{subtask_id} not found or does not belong to task #{task.id}."
     end

     researcher_type = determine_researcher_type(methods)

     begin
       agent_class = researcher_type.constantize
       unless agent_class < BaseAgent
         return "Error: #{researcher_type} is not a valid BaseAgent subclass."
       end

       agent_options = {
         task_id: subtask.id,
         parent_activity_id: agent_activity&.id,
         purpose: "Research: #{subtask.title}"
       }

       agent_class.enqueue(
         "Conduct research on: #{subtask.title}\n\n#{subtask.description}\n\nUse methods: #{Array(methods).join(', ')}",
         agent_options
       )

       subtask.activate! if subtask.may_activate?

       # Event logging within activity handled by callbacks if called via tool

       # Publish system-wide event (optional, maybe redundant with callback log)
       # Event.publish("researcher_assigned", { ... })

       "Assigned research subtask #{subtask_id} ('#{subtask.title}') to #{researcher_type}."
     rescue NameError
       "Error: Researcher type '#{researcher_type}' not found."
     rescue => e
       Rails.logger.error "[ResearchCoordinatorAgent] Error assigning researcher for subtask #{subtask_id}: #{e.message}"
       "Error assigning researcher: #{e.message}"
     end
  end

  def consolidate_findings
    unless task
      return "Error: Cannot consolidate findings - Coordinator not associated with a main task."
    end

    task.reload
    completed_subtasks = task.subtasks.where(state: "completed")

    if completed_subtasks.empty?
      return "No completed research subtasks found for consolidation for task #{task.id}."
    end

    findings = completed_subtasks.map do |st| "Subtask: #{st.title}\nFindings:\n#{st.result || '(No result recorded)'}" end.join("\n\n---\n\n")

    prompt_content = <<~PROMPT
      Synthesize findings from multiple research tasks into a coherent summary.

      OVERALL RESEARCH QUESTION: #{task.title}

      INDIVIDUAL FINDINGS:
      #{findings}

      Synthesize these findings into a comprehensive summary addressing the original question.
      Highlight key conclusions, contradictions, and remaining gaps.

      FORMAT:
      SUMMARY:
      [Comprehensive summary]

      KEY INSIGHTS:
      - [Insight 1]

      CONTRADICTIONS/UNCERTAINTIES:
      - [Contradiction 1]

      GAPS/NEXT STEPS:
      - [Gap 1]
    PROMPT

    begin
      # Use the agent's LLM
      response = @llm.chat(messages: [ { role: "user", content: prompt_content } ])

      # Manually log the LLM call
      log_direct_llm_call(prompt_content, response)

      consolidated_result = response.chat_completion # or response.content

      # Store result in the parent task
      task.update!(result: consolidated_result)

      # Event logging handled by callbacks

      # Publish system event (optional)
      # Event.publish("findings_consolidated", { task_id: task.id, subtask_count: completed_subtasks.count })

      consolidated_result
    rescue => e
      Rails.logger.error "[ResearchCoordinatorAgent] LLM Error in consolidate_findings: #{e.message}"
      "Error consolidating findings: #{e.message}"
    end
  end

  def check_existing_knowledge(query)
    # Placeholder for vector DB integration
    Rails.logger.info "[ResearchCoordinatorAgent] Tool check_existing_knowledge called (Not Implemented Yet). Query: #{query}"
    "Vector DB search not implemented yet. Cannot check existing knowledge."
  end

  def store_research_finding(finding, metadata = {})
    # Placeholder for vector DB integration
    Rails.logger.info "[ResearchCoordinatorAgent] Tool store_research_finding called (Not Implemented Yet). Finding: #{finding.truncate(50)}"
    "Vector DB storage not implemented yet. Cannot store finding."
  end

  def request_human_guidance(question, context = nil)
    unless task
      return "Error: Cannot request guidance - Coordinator not associated with a main task."
    end

    begin
      input_request = HumanInputRequest.create!(
        task: task,
        question: question,
        required: true, # Guidance is usually required
        status: "pending",
        agent_activity: agent_activity,
        metadata: { context: context }
      )

      task.wait_on_human! if task.may_wait_on_human?

      # Event log handled by callback

      # Publish system event
      Event.publish(
        "research_guidance_requested",
        { request_id: input_request.id, task_id: task.id, question: question, context: context },
        priority: Event::HIGH_PRIORITY
      )

      "Research task #{task.id} is now waiting for human guidance on: '#{question}' (Request ID: #{input_request.id})"
    rescue => e
       Rails.logger.error "[ResearchCoordinatorAgent] Error requesting human guidance: #{e.message}"
       "Error requesting human guidance: #{e.message}"
    end
  end
  # --- End Tool Implementations ---

  private

  # Helper method to determine appropriate researcher type
  def determine_researcher_type(methods)
    methods = Array(methods).map { |m| m.to_s.downcase }

    if methods.empty? || methods.any? { |m| m.include?("web") || m.include?("internet") }
      "WebResearcherAgent"
    elsif methods.any? { |m| m.include?("code") || m.include?("codebase") }
      "CodeResearcherAgent"
    elsif methods.any? { |m| m.include?("summarize") || m.include?("summary") }
      "SummarizerAgent"
    # Add more specific researcher types here based on methods if needed
    # elsif methods.include?("database")
    #   "DatabaseResearcherAgent"
    else
      # Default to web researcher if type cannot be determined
      Rails.logger.warn "[ResearchCoordinatorAgent] Could not determine specific researcher type for methods: #{methods}. Defaulting to WebResearcherAgent."
      "WebResearcherAgent"
    end
  end
end
