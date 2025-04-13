# CodeResearcherAgent: Specializes in researching and understanding code
# Used for finding code examples, patterns, and documentation
class CodeResearcherAgent < BaseAgent
  # Define queue
  def self.queue_name
    :code_researcher
  end

  # Limit concurrency
  def self.concurrency_limit
    3
  end

  # Tools that the code researcher can use
  tool :analyze_code_question, "Break down a code-related research question"
  tool :search_for_examples, "Search for code examples on a topic"
  tool :explain_code, "Explain how a piece of code works"
  tool :find_best_practices, "Find best practices for a particular coding task"
  tool :take_notes, "Record important code information discovered"
  tool :compile_findings, "Compile research notes into structured findings"

  # Tool implementation: Analyze a code research question
  def analyze_code_question(question)
    # Create a prompt for the LLM to analyze the question
    prompt = <<~PROMPT
      I need to break down the following code-related research question:

      QUESTION: #{question}

      Please analyze this question and identify:
      1. The core technical concepts involved
      2. The programming languages or frameworks that are likely relevant
      3. The type of answer being sought (e.g., code example, explanation, comparison)
      4. What a good answer would include

      FORMAT YOUR RESPONSE AS:

      CORE CONCEPTS:
      - [Concept 1]
      - [Concept 2]

      RELEVANT TECHNOLOGIES:
      - [Language/Framework 1]
      - [Language/Framework 2]

      ANSWER TYPE:
      [Type of answer being sought]

      GOOD ANSWER INCLUDES:
      - [Element 1]
      - [Element 2]
    PROMPT

    # Use a thinking model for analysis
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

    # Return the analysis
    result.content
  end

  # Tool implementation: Search for code examples
  def search_for_examples(topic, language = nil)
    language_str = language.present? ? " in #{language}" : ""

    # Create a prompt for the LLM to provide code examples
    prompt = <<~PROMPT
      I need to find code examples for the following topic#{language_str}:

      TOPIC: #{topic}

      Based on your knowledge, please provide:
      1. 2-3 realistic code examples that demonstrate this concept/approach
      2. Brief explanations of how each example works
      3. Common variations or alternatives to these examples

      FORMAT YOUR RESPONSE AS:

      ## Example 1
      ```#{language || 'code'}
      [Clear, well-commented code example]
      ```

      **Explanation**: [How this code works and what it accomplishes]

      ## Example 2
      ```#{language || 'code'}
      [Clear, well-commented code example]
      ```

      **Explanation**: [How this code works and what it accomplishes]

      ## Common Variations
      [Describe alternative approaches or variations]
    PROMPT

    # Use a code-focused model
    code_model = Regent::LLM.new(REGENT_MODEL_DEFAULTS[:tools], temperature: 0.2)
    result = code_model.invoke(prompt)

    # Log this LLM call
    if agent_activity
      agent_activity.llm_calls.create!(
        provider: "openrouter",
        model: REGENT_MODEL_DEFAULTS[:tools],
        prompt: prompt,
        response: result.content,
        tokens_used: (result.input_tokens || 0) + (result.output_tokens || 0)
      )
    end

    # Return the code examples
    result.content
  end

  # Tool implementation: Explain code
  def explain_code(code, language = nil)
    # Create a prompt for the LLM to explain the code
    prompt = <<~PROMPT
      Please provide a detailed explanation of the following code#{language ? " (#{language})" : ""}:

      ```
      #{code}
      ```

      I need to understand:
      1. What this code does, line by line
      2. The overall purpose and functionality
      3. Any notable patterns or techniques being used
      4. Potential issues, edge cases, or improvements

      FORMAT YOUR RESPONSE AS:

      ## Overall Purpose
      [Brief description of what this code accomplishes]

      ## Line-by-Line Explanation
      [Detailed walkthrough of the code]

      ## Key Patterns/Techniques
      - [Pattern/technique 1]
      - [Pattern/technique 2]

      ## Potential Improvements
      - [Suggestion 1]
      - [Suggestion 2]
    PROMPT

    # Use a code-focused model
    code_model = Regent::LLM.new(REGENT_MODEL_DEFAULTS[:tools], temperature: 0.2)
    result = code_model.invoke(prompt)

    # Log this LLM call
    if agent_activity
      agent_activity.llm_calls.create!(
        provider: "openrouter",
        model: REGENT_MODEL_DEFAULTS[:tools],
        prompt: prompt,
        response: result.content,
        tokens_used: (result.input_tokens || 0) + (result.output_tokens || 0)
      )
    end

    # Return the explanation
    result.content
  end

  # Tool implementation: Find best practices
  def find_best_practices(topic, language = nil)
    language_str = language.present? ? " in #{language}" : ""

    # Create a prompt for the LLM to provide best practices
    prompt = <<~PROMPT
      I need to research best practices for the following#{language_str}:

      TOPIC: #{topic}

      Please provide:
      1. Current industry best practices for this topic
      2. Common anti-patterns or mistakes to avoid
      3. Examples of good implementation where relevant
      4. How these practices have evolved (if applicable)

      FORMAT YOUR RESPONSE AS:

      ## Best Practices
      1. [Best practice 1]
      2. [Best practice 2]
      3. [Best practice 3]

      ## Anti-patterns to Avoid
      1. [Anti-pattern 1]
      2. [Anti-pattern 2]

      ## Implementation Examples
      ```#{language || 'code'}
      [Example of good implementation]
      ```

      ## Evolution of Practices
      [How approaches to this have changed over time]
    PROMPT

    # Use a thinking model
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

    # Return the best practices
    result.content
  end

  # Tool implementation: Take research notes - reused from WebResearcherAgent
  def take_notes(note)
    return "Error: No task available to store notes" unless task

    # Add this note to the task's metadata
    current_notes = task.metadata&.dig("research_notes") || []
    updated_notes = current_notes + [ note ]

    # Update the task's metadata
    task.update!(
      metadata: (task.metadata || {}).merge({ "research_notes" => updated_notes })
    )

    # Record this note as an event
    agent_activity.events.create!(
      event_type: "research_note_added",
      data: {
        task_id: task.id,
        note: note
      }
    )

    "Research note recorded: #{note}"
  end

  # Tool implementation: Compile findings - reused from WebResearcherAgent
  def compile_findings
    return "Error: No task available to compile findings" unless task

    # Get all the notes we've collected
    notes = task.metadata&.dig("research_notes") || []

    if notes.empty?
      return "No research notes found to compile. Use take_notes tool first."
    end

    # Format the notes for the prompt
    formatted_notes = notes.map.with_index { |note, i| "#{i+1}. #{note}" }.join("\n\n")

    # Create a prompt for the LLM to compile findings
    prompt = <<~PROMPT
      I've collected the following code research notes on the topic: #{task.title}

      RESEARCH NOTES:
      #{formatted_notes}

      Please synthesize these notes into comprehensive research findings that:
      1. Summarize the key information discovered about the code/technology
      2. Organize the code examples and patterns in a logical structure
      3. Highlight important technical considerations and best practices
      4. Note any limitations or caveats in the research

      FORMAT YOUR RESPONSE AS:

      # CODE RESEARCH FINDINGS: #{task.title}

      ## Summary
      [Brief summary of findings]

      ## Key Concepts & Patterns
      [Organized presentation of key technical information]

      ## Code Examples
      [Relevant code examples with explanations]

      ## Best Practices & Considerations
      [Important technical considerations]

      ## Limitations & Further Research
      [Any limitations or areas for further investigation]
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

    # Store the findings in the task result
    task.update!(result: result.content)

    # Create an event for task completion
    if task.may_complete?
      task.complete!

      # Publish a research completed event
      Event.publish(
        "research_subtask_completed",
        {
          subtask_id: task.id,
          result: result.content
        }
      )

      "Code research findings compiled and task marked as complete"
    else
      "Code research findings compiled but task could not be marked complete from its current state"
    end
  end
end
