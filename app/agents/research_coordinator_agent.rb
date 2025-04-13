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

  # Tools that the research coordinator can use
  tool :analyze_research_question, "Break down a research question into specific research tasks"
  tool :create_research_subtask, "Create a subtask for a specific research area"
  tool :assign_researcher, "Assign a research subtask to an appropriate researcher agent"
  tool :consolidate_findings, "Combine and synthesize research findings"
  tool :check_existing_knowledge, "Check if we already have information on a topic in our database"
  tool :semantic_memory, "Store and retrieve information using vector embeddings"
  tool :store_research_finding, "Store a research finding in the vector database"
  tool :request_human_guidance, "Request guidance from a human on research direction"

  # Handle new research task event
  def handle_new_research_task(event)
    task_id = event.data["task_id"]
    return if task_id.blank?

    task = Task.find(task_id)

    run("Plan research approach for new task:\n" +
        "Research Task: #{task.title}\n" +
        "Description: #{task.description}\n" +
        "Determine the best research strategy and break this down into focused subtasks.")
  end

  # Handle research completion event
  def handle_research_completed(event)
    subtask_id = event.data["subtask_id"]
    return if subtask_id.blank?

    subtask = Task.find(subtask_id)
    parent_task = subtask.parent
    result = event.data["result"] || "No findings provided"

    run("Integrate completed research findings and determine next steps:\n" +
        "Subtask: #{subtask.title}\n" +
        "Parent Research: #{parent_task.title}\n" +
        "Findings: #{result}\n" +
        "Consider how these findings impact the overall research goals.")
  end

  # Handle research failure event
  def handle_research_failed(event)
    subtask_id = event.data["subtask_id"]
    return if subtask_id.blank?

    subtask = Task.find(subtask_id)
    parent_task = subtask.parent
    error = event.data["error"] || "Research failed with unknown error"

    run("Address research failure and determine recovery strategy:\n" +
        "Subtask: #{subtask.title}\n" +
        "Parent Research: #{parent_task.title}\n" +
        "Error: #{error}\n" +
        "Consider alternative research approaches or sources.")
  end

  # Tool implementations
  def analyze_research_question(research_question)
    # Create a prompt for the LLM to break down the research
    prompt = <<~PROMPT
      I need to break down the following research question into specific, actionable research tasks:

      RESEARCH QUESTION: #{research_question}

      Please analyze this question and break it down into 3-5 focused research subtasks.
      For each subtask, provide:
      1. A clear research focus (what specific information we need)
      2. Suggested research methods or sources
      3. How this contributes to answering the overall question

      FORMAT YOUR RESPONSE LIKE THIS:

      Research Task 1: [FOCUS]
      Methods: [SUGGESTED METHODS/SOURCES]
      Contribution: [HOW THIS HELPS THE OVERALL QUESTION]

      Research Task 2: [FOCUS]
      Methods: [SUGGESTED METHODS/SOURCES]
      Contribution: [HOW THIS HELPS THE OVERALL QUESTION]

      ...and so on.

      Finally, provide a brief research plan explaining the order in which these tasks should be approached and why.
    PROMPT

    # Use a thinking model for complex analysis
    thinking_model = Regent::LLM.new(REGENT_MODEL_DEFAULTS[:thinking], temperature: 0.4)
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

  def create_research_subtask(title, description, methods = nil)
    # Validate that we have a parent task
    unless task
      return "Error: No parent research task available to create subtask"
    end

    # Create the research subtask with parent association
    metadata = {}
    metadata[:research_methods] = methods if methods.present?

    subtask = task.subtasks.create!(
      title: title,
      description: description,
      priority: "normal",
      state: "pending",
      metadata: metadata
    )

    # Create an event for the new subtask
    agent_activity.events.create!(
      event_type: "research_subtask_created",
      data: {
        subtask_id: subtask.id,
        parent_id: task.id,
        title: title
      }
    )

    # Also publish this as a system event
    Event.publish(
      "research_subtask_created",
      {
        subtask_id: subtask.id,
        parent_id: task.id,
        title: title,
        methods: methods
      }
    )

    "Created research subtask '#{title}' with ID #{subtask.id}"
  end

  def assign_researcher(subtask_id, methods = [])
    # Find the subtask
    subtask = Task.find(subtask_id)

    # Determine the appropriate researcher type based on methods
    researcher_type = determine_researcher_type(methods)

    begin
      # Try to get the agent class
      agent_class = researcher_type.constantize

      # Ensure it's a BaseAgent subclass
      unless agent_class < BaseAgent
        return "Error: #{researcher_type} is not a valid agent type"
      end

      # Create options for the agent
      agent_options = {
        task_id: subtask.id,
        parent_activity_id: agent_activity.id,
        purpose: "Research: #{subtask.title}"
      }

      # Enqueue the agent job
      agent_class.enqueue(
        "Conduct research on: #{subtask.title}\n\n#{subtask.description}\n\nUse methods: #{methods.join(', ')}",
        agent_options
      )

      # Update subtask state to active
      subtask.activate! if subtask.may_activate?

      # Create event for assignment
      agent_activity.events.create!(
        event_type: "researcher_assigned",
        data: {
          subtask_id: subtask.id,
          researcher_type: researcher_type,
          methods: methods
        }
      )

      "Assigned research subtask #{subtask_id} to #{researcher_type}"
    rescue NameError => e
      "Error: Researcher type '#{researcher_type}' not found: #{e.message}"
    rescue => e
      "Error assigning researcher: #{e.message}"
    end
  end

  def consolidate_findings
    return "Error: No parent research task available" unless task

    # Get all completed research subtasks
    completed_subtasks = task.subtasks.where(state: "completed")

    if completed_subtasks.empty?
      return "No completed research subtasks found for consolidation"
    end

    # Compile findings from completed subtasks
    findings = completed_subtasks.map do |subtask|
      "Research: #{subtask.title}\n" +
      "Findings: #{subtask.result}"
    end.join("\n\n")

    # Create a prompt for the LLM to synthesize findings
    prompt = <<~PROMPT
      I need to synthesize findings from multiple research tasks into a coherent summary:

      RESEARCH QUESTION: #{task.title}

      INDIVIDUAL FINDINGS:
      #{findings}

      Please synthesize these findings into a comprehensive summary that:
      1. Addresses the original research question
      2. Integrates insights from all research subtasks
      3. Highlights key conclusions and any contradictions
      4. Identifies remaining gaps or questions

      FORMAT YOUR RESPONSE AS:

      SUMMARY:
      [Comprehensive summary of all findings]

      KEY INSIGHTS:
      - [Key insight 1]
      - [Key insight 2]
      - [etc.]

      REMAINING QUESTIONS:
      - [Question 1]
      - [Question 2]
      - [etc.]
    PROMPT

    # Use a thinking model for synthesis
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

    # Store this consolidated result
    task.update(result: result.content)

    # Return the consolidated findings
    result.content
  end

  def check_existing_knowledge(query)
    # This is a placeholder - will be implemented with vector DB
    "This tool will search our vector database for relevant existing knowledge. Functionality will be implemented when vector DB integration is complete."
  end

  def store_research_finding(finding, metadata = {})
    # This is a placeholder - will be implemented with vector DB
    "This tool will store research findings in our vector database. Functionality will be implemented when vector DB integration is complete."
  end

  def request_human_guidance(question, context = nil)
    # Create a human input request
    input_request = HumanInputRequest.create!(
      task: task,
      question: question,
      required: true,
      status: "pending",
      agent_activity: agent_activity,
      metadata: { context: context }
    )

    # Change task state to waiting
    if task.may_wait_on_human?
      task.wait_on_human!
    end

    # Publish event for dashboard notification
    Event.publish(
      "research_guidance_requested",
      {
        request_id: input_request.id,
        task_id: task.id,
        question: question,
        context: context
      },
      priority: Event::HIGH_PRIORITY
    )

    "Research task is now waiting for human guidance on: '#{question}'"
  end

  private

  # Helper method to determine appropriate researcher type
  def determine_researcher_type(methods)
    methods = Array(methods).map(&:downcase)

    if methods.empty? || methods.include?("web") || methods.include?("internet")
      "WebResearcherAgent"
    elsif methods.include?("code") || methods.include?("codebase")
      "CodeResearcherAgent"
    elsif methods.include?("summarize") || methods.include?("summary")
      "SummarizerAgent"
    else
      # Default to web researcher if we can't determine
      "WebResearcherAgent"
    end
  end
end
