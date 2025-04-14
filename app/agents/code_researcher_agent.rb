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

  # --- Tools ---
  tool :analyze_code_question, "Break down a code-related research question" do |question|
    analyze_code_question(question)
  end

  tool :search_for_examples, "Search for code examples on a topic" do |topic, language = nil|
    search_for_examples(topic, language)
  end

  tool :explain_code, "Explain how a piece of code works" do |code, language = nil|
    explain_code(code, language)
  end

  tool :find_best_practices, "Find best practices for a particular coding task" do |topic, language = nil|
    find_best_practices(topic, language)
  end

  tool :take_notes, "Record important code information discovered" do |note|
    take_notes(note)
  end

  tool :compile_findings, "Compile research notes into structured findings" do
    compile_findings
  end
  # --- End Tools ---

  # --- Core Logic ---
  def run(input = nil) # Input should be the code-related question
    before_run(input)
    question = input || task&.title || "No question provided."

    unless task
      Rails.logger.warn "[CodeResearcherAgent] Running without an associated task record."
    end

    result_message = "Code research run completed for: #{question.truncate(100)}"
    begin
      Rails.logger.info "[CodeResearcherAgent-#{task&.id || 'no-task'}] Starting research for: #{question}"

      # Step 1: Analyze the question
      analysis = execute_tool(:analyze_code_question, question)
      execute_tool(:take_notes, "Initial Question Analysis:\n#{analysis}")

      # TODO: Parse analysis to determine next steps (e.g., search examples vs. explain code)
      # Placeholder: Always search for examples and best practices

      # Step 2: Search for Examples
      examples_result = execute_tool(:search_for_examples, question) # Language could be extracted from analysis
      execute_tool(:take_notes, "Code Examples Found:\n#{examples_result}")

      # Step 3: Find Best Practices
      practices_result = execute_tool(:find_best_practices, question) # Language could be extracted
      execute_tool(:take_notes, "Best Practices Found:\n#{practices_result}")

      # Step 4: Compile findings
      Rails.logger.info "[CodeResearcherAgent-#{task&.id || 'no-task'}] Compiling findings..."
      final_findings = execute_tool(:compile_findings)
      result_message = final_findings

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
  def analyze_code_question(question)
    prompt_content = <<~PROMPT
      Analyze the following code-related research question:

      QUESTION: #{question}

      Identify:
      1. Core technical concepts
      2. Relevant programming languages/frameworks
      3. Type of answer sought (example, explanation, comparison)
      4. What a good answer would include

      FORMAT:
      CORE CONCEPTS:
      - [Concept 1]

      RELEVANT TECHNOLOGIES:
      - [Language/Framework 1]

      ANSWER TYPE:
      [Type]

      GOOD ANSWER INCLUDES:
      - [Element 1]
    PROMPT

    begin
      # Use agent's LLM
      response = @llm.chat(messages: [ { role: "user", content: prompt_content } ])
      # Manually log the LLM call
      log_direct_llm_call(prompt_content, response)
      response.chat_completion # or response.content
    rescue => e
      Rails.logger.error "[CodeResearcherAgent] LLM Error in analyze_code_question: #{e.message}"
      "Error analyzing code question: #{e.message}"
    end
  end

  def search_for_examples(topic, language = nil)
    language_str = language.present? ? " in #{language}" : ""

    prompt_content = <<~PROMPT
      Find code examples for the topic#{language_str}:

      TOPIC: #{topic}

      Provide:
      1. 2-3 realistic, well-commented code examples.
      2. Brief explanations for each.
      3. Common variations or alternatives.

      FORMAT:
      ## Example 1
      ```#{language || 'code'}
      [Code]
      ```
      **Explanation**: [Explanation]

      ## Example 2
      ...

      ## Common Variations
      [Variations]
    PROMPT

    begin
      # Use agent's LLM
      response = @llm.chat(messages: [ { role: "user", content: prompt_content } ])
      # Manually log the LLM call
      log_direct_llm_call(prompt_content, response)
      response.chat_completion # or response.content
    rescue => e
      Rails.logger.error "[CodeResearcherAgent] LLM Error in search_for_examples: #{e.message}"
      "Error searching for code examples: #{e.message}"
    end
  end

  def explain_code(code, language = nil)
    prompt_content = <<~PROMPT
      Provide a detailed explanation of the following code#{language ? " (#{language})" : ""}:

      ```#{language || 'code'}
      #{code}
      ```

      Explain:
      1. Overall purpose and functionality.
      2. Line-by-line walkthrough (if feasible, otherwise key sections).
      3. Notable patterns or techniques.
      4. Potential issues, edge cases, or improvements.

      FORMAT:
      ## Overall Purpose
      [Description]

      ## Explanation
      [Walkthrough/Key Sections]

      ## Key Patterns/Techniques
      - [Pattern 1]

      ## Potential Improvements
      - [Suggestion 1]
    PROMPT

    begin
      # Use agent's LLM (consider a code-specific model if configured)
      response = @llm.chat(messages: [ { role: "user", content: prompt_content } ])
      # Manually log the LLM call
      log_direct_llm_call(prompt_content, response)
      response.chat_completion # or response.content
    rescue => e
      Rails.logger.error "[CodeResearcherAgent] LLM Error in explain_code: #{e.message}"
      "Error explaining code: #{e.message}"
    end
  end

  def find_best_practices(topic, language = nil)
    language_str = language.present? ? " in #{language}" : ""

    prompt_content = <<~PROMPT
      Research best practices for#{language_str}:

      TOPIC: #{topic}

      Provide:
      1. Current industry best practices.
      2. Common anti-patterns/mistakes to avoid.
      3. Examples of good implementation (if relevant).
      4. Evolution of these practices (if applicable).

      FORMAT:
      ## Best Practices
      1. [Practice 1]

      ## Anti-patterns to Avoid
      1. [Anti-pattern 1]

      ## Implementation Examples
      ```#{language || 'code'}
      [Code Example]
      ```

      ## Evolution of Practices
      [Description]
    PROMPT

    begin
      # Use agent's LLM
      response = @llm.chat(messages: [ { role: "user", content: prompt_content } ])
      # Manually log the LLM call
      log_direct_llm_call(prompt_content, response)
      response.chat_completion # or response.content
    rescue => e
      Rails.logger.error "[CodeResearcherAgent] LLM Error in find_best_practices: #{e.message}"
      "Error finding best practices: #{e.message}"
    end
  end

  # Reusing take_notes from WebResearcherAgent logic (can be extracted to a concern/module later)
  def take_notes(note)
    unless task
      return "Error: Cannot take notes - Agent not associated with a task."
    end

    begin
      current_notes = task.metadata&.dig("research_notes") || []
      updated_notes = current_notes + [ note ]
      task.update!(metadata: (task.metadata || {}).merge({ "research_notes" => updated_notes }))

      # Logging handled by callbacks

      "Code research note recorded: #{note.truncate(100)}"
    rescue => e
      Rails.logger.error "[CodeResearcherAgent] Error taking notes for task #{task.id}: #{e.message}"
      "Error recording note: #{e.message}"
    end
  end

  # Reusing compile_findings from WebResearcherAgent logic (can be extracted later)
  def compile_findings
    unless task
      return "Error: Cannot compile findings - Agent not associated with a task."
    end

    notes = task.metadata&.dig("research_notes") || []
    if notes.empty?
      return "No code research notes found to compile for task #{task.id}. Use take_notes tool first."
    end

    formatted_notes = notes.map.with_index { |note, i| "Note #{i + 1}:\n#{note}" }.join("\n\n---\n\n")

    prompt_content = <<~PROMPT
      Synthesize the following code research notes regarding '#{task.title}'.

      RESEARCH NOTES:
      #{formatted_notes}

      Compile these notes into comprehensive findings.
      Summarize key info, organize examples/patterns, highlight technical considerations/best practices, and note limitations.

      FORMAT:
      # CODE RESEARCH FINDINGS: #{task.title}

      ## Summary
      [Brief summary]

      ## Key Concepts & Patterns
      [Organized technical info]

      ## Code Examples
      [Relevant examples with explanations]

      ## Best Practices & Considerations
      [Technical considerations]

      ## Limitations & Further Research
      [Limitations/Gaps]
    PROMPT

    begin
      # Use agent's LLM
      response = @llm.chat(messages: [ { role: "user", content: prompt_content } ])
      compiled_result = response.chat_completion # or response.content

      # Manually log the LLM call
      log_direct_llm_call(prompt_content, response)

      # Store findings as the task result
      task.update!(result: compiled_result)
      task.complete! if task.may_complete?

      # Publish event if this is a subtask
      if task.parent_id
        Event.publish(
          "research_subtask_completed",
          { subtask_id: task.id, parent_id: task.parent_id, result: compiled_result }
        )
      end

      compiled_result
    rescue => e
      Rails.logger.error "[CodeResearcherAgent] LLM Error in compile_findings for task #{task.id}: #{e.message}"
      "Error compiling findings: #{e.message}"
    end
  end
  # --- End Tool Implementations ---
end
