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
  tool :ask_llm_question, "Ask a question to an LLM and get its response"
  tool :save_response, "Save a response to a text file"
  tool :search_web, "Search the web for information"

  # Ask a question directly to the LLM
  def ask_llm_question(question)
    # Create a direct LLM query (different from the agent itself)
    # This shows how to call a different LLM model directly within a tool
    llm = Regent::LLM.new("deepseek/deepseek-chat-v3-0324", temperature: 0.3)

    # Track the fact that we're making this call in our activity
    agent_activity.events.create!(
      event_type: "llm_direct_query",
      data: { question: question, model: llm.model }
    ) if agent_activity

    # Make the actual LLM call
    begin
      result = llm.invoke("You are a helpful AI assistant being interviewed. Please answer the following question professionally, truthfully, and concisely: #{question}")

      # Record this call in our database if we have an activity
      if agent_activity
        agent_activity.llm_calls.create!(
          provider: "openrouter",
          model: llm.model,
          prompt: question,
          response: result.content,
          tokens_used: (result.input_tokens || 0) + (result.output_tokens || 0)
        )
      end

      # Return just the content
      result.content
    rescue => e
      "Error getting response: #{e.message}"
    end
  end

  # Save a response to a file
  def save_response(question, answer, filename = nil)
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
  def search_web(query)
    "This is a simulated web search result for: '#{query}'. In a real implementation, this would connect to a search API."
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
