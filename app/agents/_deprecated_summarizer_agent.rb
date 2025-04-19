# SummarizerAgent: Specializes in consolidating and summarizing information
# Used for synthesizing research findings, documents, or any text content
class SummarizerAgent < BaseAgent
  # Define queue
  def self.queue_name
    :summarizer
  end

  # Limit concurrency
  def self.concurrency_limit
    3
  end

  # --- Tools ---
  tool :summarize_texts, "Summarize a text or an array of texts, condensing it while preserving key information (args: text: <string|array>, max_length: <short|medium|long default(medium))" do |text:, max_length: "medium"|
    summarize_text(text, max_length)
  end

  tool :extract_key_points, "Extract the most important points from text" do |text|
    extract_key_points(text)
  end

  tool :combine_summaries, "Combine multiple summaries (stored in task metadata) into a coherent whole" do
    combine_summaries
  end

  tool :generate_insights, "Generate insights and observations from text or the combined summary" do |text = nil|
    generate_insights(text)
  end

  tool :compile_final_summary, "Compile all stored information (summaries, points, insights) into a final, structured summary" do
    compile_final_summary
  end
  # --- End Tools ---

  # --- Core Logic ---
  def run(input = nil) # Input should contain the text/details to summarize
    before_run(input)
    # Trust the input from AgentJob, which should now contain task details/instructions
    text_to_process = input.present? ? input : ""

    unless task
      Rails.logger.warn "[SummarizerAgent] Running without an associated task record. Metadata persistence will be skipped."
    end

    if text_to_process.blank?
      result = "SummarizerAgent Error: No input text provided."
      Rails.logger.error result
      @session_data[:output] = result
      after_run(result)
      return result
    end

    result_message = "Summarization run completed."
    begin
      Rails.logger.info "[SummarizerAgent-#{task&.id || 'no-task'}] Starting summarization..."

      # Step 1: Initial Summary
      summary = execute_tool(:summarize_text, text_to_process)
      # Note: summarize_text tool already updates task metadata["summaries"]

      # Step 2: Extract Key Points
      key_points = execute_tool(:extract_key_points, text_to_process)
      # Note: extract_key_points tool already updates task metadata["key_points"]

      # Step 3: Generate Insights (from the summary)
      insights = execute_tool(:generate_insights, summary)
      # Note: generate_insights tool already updates task metadata["insights"]

      # Step 4: Compile Final Summary
      # This tool reads from metadata populated by previous steps
      final_summary = execute_tool(:compile_final_summary)
      # Note: compile_final_summary tool updates task.result and marks complete

      result_message = final_summary

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
  def summarize_text(text, max_length = "medium")
    length_guide = case max_length.downcase
    when "short" then "around 10-15% of original length."
    when "medium" then "around 20-30% of original length."
    when "long" then "around 30-40% of original length."
    else "around 20-30% of original length."
    end

    prompt_content = <<~PROMPT
      Summarize the following text, preserving key information:

      TEXT:
      #{text}

      INSTRUCTIONS:
      - #{length_guide}
      - Preserve essential info/facts/arguments.
      - Maintain original tone/perspective.
      - Eliminate redundancies.
      - Ensure summary can stand alone.

      FORMAT:
      [Provide a coherent, flowing summary in paragraph form]
    PROMPT

    begin
      # Use agent's LLM
      response = @llm.chat(messages: [ { role: "user", content: prompt_content } ])
      summary_content = response.chat_completion # or response.content

      # Manually log the LLM call
      log_direct_llm_call(prompt_content, response)

      # Store summary in task metadata (still relevant for this agent's state)
      if task
        summaries = task.metadata&.dig("summaries") || []
        task.update!(metadata: (task.metadata || {}).merge({ "summaries" => summaries + [ summary_content ] }))
      end

      summary_content
    rescue => e
      Rails.logger.error "[SummarizerAgent] LLM Error in summarize_text: #{e.message}"
      "Error summarizing text: #{e.message}"
    end
  end

  def extract_key_points(text)
    prompt_content = <<~PROMPT
      Extract the 5-10 most important key points from the following text:

      TEXT:
      #{text}

      INSTRUCTIONS:
      - Present each as a concise bullet point.
      - Use original wording where possible.
      - Include critical numbers/stats/quotes.

      FORMAT:
      KEY POINTS:
      - [Point 1]
      - [Point 2]
      ...
    PROMPT

    begin
      # Use agent's LLM (can use default, or specify fast if needed)
      response = @llm.chat(messages: [ { role: "user", content: prompt_content } ])
      key_points_content = response.chat_completion # or response.content

      # Manually log the LLM call
      log_direct_llm_call(prompt_content, response)

      # Store key points in task metadata
      if task
        key_points = task.metadata&.dig("key_points") || []
        # Consider parsing the bullet points if needed downstream
        task.update!(metadata: (task.metadata || {}).merge({ "key_points" => key_points + [ key_points_content ] }))
      end

      key_points_content
    rescue => e
      Rails.logger.error "[SummarizerAgent] LLM Error in extract_key_points: #{e.message}"
      "Error extracting key points: #{e.message}"
    end
  end

  def combine_summaries
    unless task
      return "Error: Cannot combine summaries - Agent not associated with a task."
    end

    summaries = task.metadata&.dig("summaries") || []
    if summaries.empty?
      return "No summaries found in task metadata to combine. Use summarize_text tool first."
    end

    formatted_summaries = summaries.map.with_index { |summary, i| "Summary #{i + 1}:\n#{summary}" }.join("\n\n---\n\n")

    prompt_content = <<~PROMPT
      Combine these summaries into a single coherent summary:

      #{formatted_summaries}

      INSTRUCTIONS:
      - Integrate all summaries comprehensively.
      - Eliminate redundancies.
      - Resolve contradictions or note different perspectives.
      - Organize logically.
      - Preserve all key information.

      FORMAT:
      [Provide a single, coherent combined summary in paragraph form]
    PROMPT

    begin
      # Use agent's LLM
      response = @llm.chat(messages: [ { role: "user", content: prompt_content } ])
      combined_summary_content = response.chat_completion # or response.content

      # Manually log the LLM call
      log_direct_llm_call(prompt_content, response)

      # Store combined summary in task metadata
      task.update!(metadata: (task.metadata || {}).merge({ "combined_summary" => combined_summary_content }))

      combined_summary_content
    rescue => e
      Rails.logger.error "[SummarizerAgent] LLM Error in combine_summaries: #{e.message}"
      "Error combining summaries: #{e.message}"
    end
  end

  def generate_insights(text = nil)
    unless task
      return "Error: Cannot generate insights - Agent not associated with a task."
    end

    content = text || task.metadata&.dig("combined_summary") || task.description
    if content.blank?
       return "Error: No content available (text parameter, combined_summary metadata, or task description) to generate insights from."
    end

    prompt_content = <<~PROMPT
      Generate key insights, observations, and implications from the following content:

      CONTENT:
      #{content}

      INSTRUCTIONS:
      - Identify 3-5 significant insights/patterns.
      - Note implications/conclusions.
      - Highlight surprising findings.
      - Consider different perspectives.
      - Suggest potential applications/actions.

      FORMAT:
      KEY INSIGHTS:
      1. [Insight 1]
      2. [Insight 2]

      IMPLICATIONS:
      - [Implication 1]
      ...
    PROMPT

    begin
      # Use agent's LLM
      response = @llm.chat(messages: [ { role: "user", content: prompt_content } ])
      insights_content = response.chat_completion # or response.content

      # Manually log the LLM call
      log_direct_llm_call(prompt_content, response)

      # Store insights in task metadata
      task.update!(metadata: (task.metadata || {}).merge({ "insights" => insights_content }))

      insights_content
    rescue => e
      Rails.logger.error "[SummarizerAgent] LLM Error in generate_insights: #{e.message}"
      "Error generating insights: #{e.message}"
    end
  end

  def compile_final_summary
    unless task
      return "Error: Cannot compile summary - Agent not associated with a task."
    end

    combined_summary = task.metadata&.dig("combined_summary") || ""
    # Assuming key_points are stored as an array of strings
    key_points_texts = task.metadata&.dig("key_points") || []
    formatted_key_points = key_points_texts.join("\n\n") # Combine multiple extractions
    insights = task.metadata&.dig("insights") || ""

    base_content = ""
    base_content += "COMBINED SUMMARY:\n#{combined_summary}\n\n" if combined_summary.present?
    base_content += "KEY POINTS:\n#{formatted_key_points}\n\n" if formatted_key_points.present?
    base_content += "INSIGHTS:\n#{insights}\n\n" if insights.present?

    if base_content.blank?
      return "Insufficient content found in task metadata (combined_summary, key_points, insights) to compile a final summary. Please use other tools first."
    end

    prompt_content = <<~PROMPT
      Compile a comprehensive final summary using the following component parts:

      #{base_content}

      INSTRUCTIONS:
      - Create a structured final summary integrating all information.
      - Begin with an executive summary (1-2 paragraphs).
      - Include key points organized by theme.
      - Incorporate important insights/implications.
      - Conclude with recommendations if applicable.

      FORMAT:
      # FINAL SUMMARY: #{task.title}

      ## Executive Summary
      [Concise overview]

      ## Key Findings
      [Organized key points/info]

      ## Insights & Implications
      [Analysis and meaning]

      ## Conclusion
      [Final thoughts/recommendations]
    PROMPT

    begin
      # Use agent's LLM
      response = @llm.chat(messages: [ { role: "user", content: prompt_content } ])
      final_summary_content = response.chat_completion # or response.content

      # Manually log the LLM call
      log_direct_llm_call(prompt_content, response)

      # Store the final summary in the task result
      task.update!(result: final_summary_content)
      task.complete! if task.may_complete?

      # Publish completion event if it's a subtask
      if task.parent_id
        Event.publish(
          "research_subtask_completed", # Or a generic subtask_completed?
          { subtask_id: task.id, parent_id: task.parent_id, result: final_summary_content }
        )
      end

      final_summary_content
    rescue => e
      Rails.logger.error "[SummarizerAgent] LLM Error in compile_final_summary: #{e.message}"
      "Error compiling final summary: #{e.message}"
    end
  end
  # --- End Tool Implementations ---
end
