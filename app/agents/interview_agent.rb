# InterviewAgent: Asks LLM questions and records answers
class InterviewAgent < BaseAgent
  # Define queue name
  def self.queue_name
    :interview
  end

  # Limit concurrency to 3 interviews at a time
  def self.concurrency_limit
    3
  end

  # Tools that the interview agent can use
  tool :ask_llm_question, "Ask a question to an LLM and get its response" do |question|
    # Create a direct LLM query (different from the agent itself)
    # This shows how to call a different model directly within a tool
    interview_llm = Langchain::LLM::OpenRouter.new(
      api_key: ENV["OPEN_ROUTER_API_KEY"],
      default_options: {
        chat_model: "deepseek/deepseek-chat-v3-0324",
        temperature: 0.3
      }
    )

    # Track the fact that we're making this call in our activity
    agent_activity.events.create!(
      event_type: "llm_direct_query",
      data: { question: question, model: "deepseek/deepseek-chat-v3-0324" }
    ) if agent_activity

    # Make the actual LLM call
    begin
      response = interview_llm.chat(
        messages: [
          { role: "system", content: "You are a helpful AI assistant being interviewed. Please answer the following question professionally, truthfully, and concisely." },
          { role: "user", content: question }
        ]
      )

      # Record this call in our database if we have an activity
      if agent_activity
        agent_activity.llm_calls.create!(
          provider: "openrouter",
          model: response.model || "deepseek/deepseek-chat-v3-0324",
          prompt: question,
          response: response.chat_completion,
          tokens_used: (response.prompt_tokens || 0) + (response.completion_tokens || 0)
        )
      end

      # Return just the content
      response.chat_completion
    rescue => e
      "Error getting response: #{e.message}"
    end
  end

  # Save a response to a file
  tool :save_response, "Save a response to a text file" do |question, answer, filename = nil|
    # Generate a filename if not provided
    filename ||= "interview_#{Time.now.strftime('%Y%m%d_%H%M%S')}.txt"

    # Ensure the interviews directory exists
    FileUtils.mkdir_p(Rails.root.join("data", "interviews"))

    # Full path to the file
    file_path = Rails.root.join("data", "interviews", filename)

    # Write the content to the file
    File.open(file_path, "w") do |file|
      file.puts("Interview recorded at: #{Time.now}")
      file.puts("\nQuestion: #{question}")
      file.puts("\nAnswer: #{answer}")
    end

    # Create an event to track this action
    agent_activity.events.create!(
      event_type: "response_saved",
      data: {
        question: question,
        answer_preview: answer.truncate(100),
        filename: filename,
        path: file_path.to_s
      }
    ) if agent_activity

    "Response saved to #{filename}"
  end

  # Search the web for information (simulated)
  tool :search_web, "Search the web for information" do |query|
    "This is a simulated web search result for: '#{query}'. In a real implementation, this would connect to a search API."
  end

  # Override execute_chain to handle the input
  def execute_chain(input)
    # Use the LLM to decide what to do with the input
    response = @llm.chat(
      messages: [
        { role: "system", content: "You are an interview agent that can ask questions to an LLM, search the web for information, and save responses to files." },
        { role: "user", content: input }
      ]
    )
    
    # Record the LLM call
    record_llm_call(
      "openrouter",
      response.model || "unknown",
      input,
      response.chat_completion,
      response.total_tokens || 0
    )
    
    # Return the completion
    response.chat_completion
  end

  # Custom after_run to provide a summary of the interview
  def after_run
    super

    return unless task && agent_activity

    # Get all LLM calls for a summary
    llm_calls = agent_activity.llm_calls
    interview_events = agent_activity.events.where(event_type: [ "llm_direct_query", "response_saved" ])

    # Update task with summary
    task.update(
      notes: "Interview conducted with #{llm_calls.count} questions. " +
             "#{interview_events.where(event_type: 'response_saved').count} responses saved to files."
    )
  end
end
