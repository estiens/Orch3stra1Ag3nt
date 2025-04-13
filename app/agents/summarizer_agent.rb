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

  # Tools that the summarizer can use
  tool :summarize_text, "Summarize a piece of text, condensing it while preserving key information"
  tool :extract_key_points, "Extract the most important points from text"
  tool :combine_summaries, "Combine multiple summaries into a coherent whole"
  tool :generate_insights, "Generate insights and observations from the summarized content"
  tool :compile_final_summary, "Compile all information into a final, structured summary"

  # Tool implementation: Summarize a piece of text
  def summarize_text(text, max_length = "medium")
    # Define the length constraints based on the max_length parameter
    length_guide = case max_length.downcase
    when "short"
                    "Keep the summary very concise, around 10-15% of the original length."
    when "medium"
                    "Create a balanced summary, around 20-30% of the original length."
    when "long"
                    "Create a comprehensive summary, around 30-40% of the original length."
    else
                    "Create a balanced summary, around 20-30% of the original length."
    end

    # Create a prompt for the LLM to summarize the text
    prompt = <<~PROMPT
      Please summarize the following text, preserving all key information while reducing length:

      TEXT TO SUMMARIZE:
      #{text}

      INSTRUCTIONS:
      1. #{length_guide}
      2. Preserve all essential information, facts, and arguments
      3. Maintain the original tone and perspective
      4. Eliminate redundancies and less important details
      5. Ensure the summary could stand alone as a complete understanding of the original

      FORMAT:
      [Provide a coherent, flowing summary in paragraph form]
    PROMPT

    # Use a thinking model for comprehension and synthesis
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

    # Store summary in task metadata if available
    if task
      summaries = task.metadata&.dig("summaries") || []
      task.update!(
        metadata: (task.metadata || {}).merge({
          "summaries" => summaries + [ result.content ]
        })
      )
    end

    # Return the summary
    result.content
  end

  # Tool implementation: Extract key points
  def extract_key_points(text)
    # Create a prompt for the LLM to extract key points
    prompt = <<~PROMPT
      Please extract the most important key points from the following text:

      TEXT:
      #{text}

      INSTRUCTIONS:
      1. Identify the 5-10 most significant facts, claims, or arguments
      2. Present each point as a concise bullet point
      3. Use the original wording where possible
      4. Include any critical numbers, statistics, or quotes
      5. Ensure the key points represent a complete picture of the most important content

      FORMAT:
      KEY POINTS:
      - [Point 1]
      - [Point 2]
      - [Point 3]
      - etc.
    PROMPT

    # Use a fast model for extraction
    fast_model = Regent::LLM.new(REGENT_MODEL_DEFAULTS[:fast], temperature: 0.2)
    result = fast_model.invoke(prompt)

    # Log this LLM call
    if agent_activity
      agent_activity.llm_calls.create!(
        provider: "openrouter",
        model: REGENT_MODEL_DEFAULTS[:fast],
        prompt: prompt,
        response: result.content,
        tokens_used: (result.input_tokens || 0) + (result.output_tokens || 0)
      )
    end

    # Store key points in task metadata if available
    if task
      key_points = task.metadata&.dig("key_points") || []
      task.update!(
        metadata: (task.metadata || {}).merge({
          "key_points" => key_points + [ result.content ]
        })
      )
    end

    # Return the key points
    result.content
  end

  # Tool implementation: Combine summaries
  def combine_summaries
    return "Error: No task available to access summaries" unless task

    # Get all the summaries we've collected
    summaries = task.metadata&.dig("summaries") || []

    if summaries.empty?
      return "No summaries found to combine. Use summarize_text tool first."
    end

    # Format the summaries for the prompt
    formatted_summaries = summaries.map.with_index { |summary, i| "Summary #{i+1}:\n#{summary}" }.join("\n\n")

    # Create a prompt for the LLM to combine the summaries
    prompt = <<~PROMPT
      I have multiple summaries of related content that need to be combined into a single coherent summary:

      #{formatted_summaries}

      INSTRUCTIONS:
      1. Integrate all these summaries into one comprehensive summary
      2. Eliminate redundancies across the summaries
      3. Resolve any contradictions by noting different perspectives
      4. Organize the information in a logical flow
      5. Ensure all key information from each summary is preserved

      FORMAT:
      [Provide a single, coherent combined summary in paragraph form]
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

    # Store combined summary in task metadata
    task.update!(
      metadata: (task.metadata || {}).merge({
        "combined_summary" => result.content
      })
    )

    # Return the combined summary
    result.content
  end

  # Tool implementation: Generate insights
  def generate_insights(text = nil)
    return "Error: No task available to access content" unless task

    # Use provided text or try to get the combined summary from metadata
    content = text || task.metadata&.dig("combined_summary") || task.description

    # Create a prompt for the LLM to generate insights
    prompt = <<~PROMPT
      Based on the following content, please generate key insights, observations, and implications:

      CONTENT:
      #{content}

      INSTRUCTIONS:
      1. Identify 3-5 significant insights or patterns in the content
      2. Note any implications or conclusions that can be drawn
      3. Highlight any surprising or counter-intuitive findings
      4. Consider different perspectives on the information
      5. Suggest potential applications or actions based on these insights

      FORMAT:
      KEY INSIGHTS:
      1. [First insight with brief explanation]
      2. [Second insight with brief explanation]
      3. [Third insight with brief explanation]

      IMPLICATIONS:
      - [Implication 1]
      - [Implication 2]
      - [Implication 3]
    PROMPT

    # Use a thinking model for insight generation
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

    # Store insights in task metadata
    task.update!(
      metadata: (task.metadata || {}).merge({
        "insights" => result.content
      })
    )

    # Return the insights
    result.content
  end

  # Tool implementation: Compile final summary
  def compile_final_summary
    return "Error: No task available to access content" unless task

    # Get all the components we've generated
    combined_summary = task.metadata&.dig("combined_summary") || ""
    key_points = task.metadata&.dig("key_points") || []
    insights = task.metadata&.dig("insights") || ""

    # Format the components
    formatted_key_points = key_points.join("\n\n")

    # Create a composite of all our work or use what we have
    if combined_summary.present? && insights.present?
      base_content = "COMBINED SUMMARY:\n#{combined_summary}\n\nKEY POINTS:\n#{formatted_key_points}\n\nINSIGHTS:\n#{insights}"
    elsif combined_summary.present?
      base_content = "COMBINED SUMMARY:\n#{combined_summary}\n\nKEY POINTS:\n#{formatted_key_points}"
    else
      return "Insufficient content to compile a final summary. Please use the other tools first."
    end

    # Create a prompt for the LLM to compile the final summary
    prompt = <<~PROMPT
      Please compile a comprehensive final summary using all the component parts:

      #{base_content}

      INSTRUCTIONS:
      1. Create a structured final summary that integrates all of the above information
      2. Begin with an executive summary (1-2 paragraphs)
      3. Include all key points organized by theme or topic
      4. Incorporate important insights and implications
      5. Conclude with recommendations or next steps if applicable

      FORMAT YOUR RESPONSE AS:

      # FINAL SUMMARY: #{task.title}

      ## Executive Summary
      [Concise overview of the entire content]

      ## Key Findings
      [Organized presentation of all key information]

      ## Insights & Implications
      [Analysis of what the findings mean]

      ## Conclusions
      [Final thoughts and recommendations]
    PROMPT

    # Use a thinking model for final compilation
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

    # Store the final summary in the task result
    task.update!(result: result.content)

    # Mark task as complete if possible
    if task.may_complete?
      task.complete!

      # Publish completion event
      Event.publish(
        "research_subtask_completed",
        {
          subtask_id: task.id,
          result: result.content
        }
      )

      "Final summary compiled and task marked as complete"
    else
      "Final summary compiled but task could not be marked complete from its current state"
    end
  end
end
