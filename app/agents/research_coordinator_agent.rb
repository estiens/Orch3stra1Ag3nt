# ResearchCoordinatorAgent: Specialized coordinator for research tasks
# Manages the research process through multiple sub-agents
class ResearchCoordinatorAgent < BaseAgent
  include EventSubscriber
  include ResearchCoordinator::EventHandlers
  include ResearchCoordinator::Tools::ResearchManagement
  include ResearchCoordinator::Tools::KnowledgeManagement
  include ResearchCoordinator::Helpers
  include ResearchCoordinator::Prompts

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

  # --- Tools with Explicit Parameter Documentation ---
  tool :analyze_research_question, "Break down a research question into specific research tasks. Takes (research_question: <full question details>)" do |research_question:|
    analyze_research_question(research_question)
  end

  tool :create_research_subtask, "Create a subtask for a specific research area. Takes (title: <concise title>, description: <detailed instructions>, methods: <optional array of research methods>)" do |title:, description:, methods: nil|
    create_research_subtask(title, description, methods)
  end

  tool :assign_researcher, "Assign a research subtask to an appropriate researcher agent. Takes (subtask_id: <ID number>, methods: <optional array of research methods>)" do |subtask_id:, methods: []|
    assign_researcher(subtask_id, methods)
  end

  tool :consolidate_findings, "Combine and synthesize research findings from completed subtasks. Takes no parameters." do
    consolidate_findings
  end

  tool :check_existing_knowledge, "Check if we already have information on a topic in our database. Takes (query: <search query>)" do |query:|
    check_existing_knowledge(query)
  end

  tool :store_research_finding, "Store a research finding in the vector database. Takes (finding: <text to store>, metadata: <optional metadata object>)" do |finding:, metadata: {}|
    store_research_finding(finding, metadata)
  end

  tool :request_human_guidance, "Request guidance from a human on research direction. Takes (question: <specific question>, context: <optional background info>)" do |question:, context: nil|
    request_human_guidance(question, context)
  end
  # --- End Tools ---

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

    # Parse input context if provided
    context = input.is_a?(Hash) ? input[:context] : nil
    event_type = context&.dig(:event_type)

    # Log the coordinator start with context
    Rails.logger.info "[ResearchCoordinator-#{task.id}] Starting run with event_type: #{event_type || 'none'}"

    result_message = nil

    begin
      # Different logic flows based on task state and context
      if event_type == "research_subtask_failed"
        # Handle failed subtask
        subtask_id = context[:subtask_id]
        error = context[:error]
        result_message = "Research subtask #{subtask_id} failed: #{error}. Consider requesting human guidance."
      elsif event_type == "research_subtask_completed"
        # Check if all subtasks are completed
        task.reload
        completed_subtasks = task.subtasks.where(state: "completed")
        all_subtasks = task.subtasks.count

        if completed_subtasks.count == all_subtasks && all_subtasks > 0
          # All subtasks completed, consolidate findings
          Rails.logger.info "[ResearchCoordinator-#{task.id}] All research subtasks completed. Consolidating findings..."
          result_message = execute_tool(:consolidate_findings)
        else
          result_message = "Research subtask completed. #{completed_subtasks.count}/#{all_subtasks} subtasks completed."
        end
      elsif task.reload.subtasks.empty?
        Rails.logger.info "[ResearchCoordinator-#{task.id}] Analyzing research question: #{task.title}"
        # Analyze the main research question
        analysis = execute_tool(:analyze_research_question, research_question: input || task.description)

        # Parse analysis to get subtask details
        subtasks_to_create = parse_research_subtasks(analysis)

        if subtasks_to_create.any?
          Rails.logger.info "[ResearchCoordinator-#{task.id}] Creating #{subtasks_to_create.count} research subtasks..."
          subtasks_to_create.each do |subtask_data|
            # Create subtask
            create_result = execute_tool(
              :create_research_subtask,
              title: subtask_data[:title],
              description: subtask_data[:description],
              methods: subtask_data[:methods]
            )

            # Extract subtask ID (assuming create_tool returns it like "... ID 123")
            subtask_id_match = create_result.match(/ID\s*(\d+)/)
            if subtask_id_match
              subtask_id = subtask_id_match[1].to_i
              # Assign researcher based on methods
              execute_tool(:assign_researcher, subtask_id: subtask_id, methods: subtask_data[:methods])
            else
              Rails.logger.error "[ResearchCoordinator-#{task.id}] Could not extract subtask ID from create result: #{create_result}"
            end
          end
          result_message = "Analyzed research question, created and assigned #{subtasks_to_create.count} subtasks."
        else
          Rails.logger.warn "[ResearchCoordinator-#{task.id}] Analysis did not yield subtasks."
          result_message = "Analyzed research question, but no subtasks identified."
        end
      else
        # Check status and consolidate if needed
        Rails.logger.info "[ResearchCoordinator-#{task.id}] Checking research subtasks..."
        task.reload # Refresh subtask states
        completed_subtasks = task.subtasks.where(state: "completed")
        failed_subtasks = task.subtasks.where(state: "failed")
        active_subtasks = task.subtasks.where(state: "active")
        pending_subtasks = task.subtasks.where(state: "pending")

        if failed_subtasks.any?
          result_message = "One or more research subtasks failed. Needs review."
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
end
