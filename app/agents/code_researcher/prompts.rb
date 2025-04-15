# frozen_string_literal: true

module CodeResearcher
  module Prompts
    def main_loop_prompt(question:, current_notes:, examined_dirs_history:, previous_commands_history:, last_result_display:, formatted_tools:, format_instructions:, iterations:, max_iterations:)
      <<~PROMPT
      # ROLE AND GOAL
      You are a meticulous Automated Code Explorer. Your primary objective is to systematically navigate and understand the codebase to gather information that comprehensively answers the user's question.
      USER QUESTION: #{question}

    # ANTI-REPETITION DIRECTIVE
    You MUST avoid redundant actions. Do NOT:
    - Examine directories already listed below.
    - Run commands substantially similar to those already run.
    - Take notes covering information already recorded.

    # CURRENT EXPLORATION STATUS
    Iteration: #{iterations}/#{max_iterations}

    DIRECTORIES ALREADY EXAMINED (via 'examine_directory'):
    #{examined_dirs_history}

    RECENT SHELL COMMANDS ALREADY RUN (via 'shell_command'):
    #{previous_commands_history}

    NOTES TAKEN SO FAR (Significant findings discovered):
    ```
    #{current_notes}
    ```

    LAST TOOL RESULT (Output or error from your previous action):
    ```
    #{last_result_display}
    ```

    AVAILABLE TOOLS (Use these to explore and gather information):
    #{formatted_tools}

    === YOUR TASK ===
    Based on the USER QUESTION, CURRENT NOTES, and LAST TOOL RESULT, determine the single best *next action* to progress towards answering the question.

    === STRATEGIC THINKING PROCESS (Follow these steps): ===
    1.  **Analyze Goal:** Re-read the USER QUESTION. What specific information is still needed?
    2.  **Review Context:** Examine CURRENT NOTES. What parts of the codebase have been explored? What remains unknown?
    3.  **Evaluate Last Result:** Analyze the LAST TOOL RESULT.
        *   If it contains useful information (file listing, file content, search results, directory summary): What key insight does it provide? Does it suggest the next file/directory to examine? Should I use `take_notes` *now* to record this insight before moving on?
        *   If it was an error: Why did it fail (e.g., file not found, command error)? Can I try an alternative (different path, simpler command, different tool)? Should I use `take_notes` to record the obstacle?
    4.  **Plan Next Step:** Decide the most logical next exploration target (e.g., examine root directory, list files in `app/models`, read `app/controllers/users_controller.rb`, search for `User.find`).
    5.  **Select Optimal Tool:** Choose the *single tool* that directly achieves your planned next step. Prioritize `take_notes` if step 3 identified key info to save *before* exploring further.
    6.  **Formulate Action:** Construct the arguments for the chosen tool precisely.

    === TOOL USAGE GUIDELINES ===
    *   `shell_command`: Your primary exploration tool. Use specific commands:
        *   `ls -l <directory>`: To list contents of a directory. Start broad (e.g., `ls -l .`) then explore subdirectories.
        *   `cat <file_path>`: To read the contents of a *specific* file identified via `ls` or other tools.
        *   `grep <pattern> <file>`: For simple searches within a known file.
        *   **AVOID**: Generic commands like just `explore`. Be specific.
    *   `examine_directory`: Use when you need a *summary* of *all* files in a directory, processed by `code2prompt`. Useful for getting an overview of a complex area like `app/services` *before* diving into individual files with `cat`. More costly than `ls`.
    *   `search_code_base`: Use *only* when you need to find specific code snippets, function calls, or keywords *across the entire codebase* (uses `rg`). Less useful for general structure exploration than `ls` or `examine_directory`.
    *   `explain_code`: Use *sparingly* only for short, specific code snippets already retrieved via `cat` or `search_code_base` that you cannot understand from context.
    *   `take_notes`: **CRITICAL**. Use frequently to record **significant findings** directly contributing to the answer:
        *   Purpose of a directory or important file.
        *   Key logic or data flow identified.
        *   Relationships between different code parts.
        *   Direct evidence answering the USER QUESTION.
        *   Obstacles or errors encountered during exploration.
        *   **Do NOT** use for trivial actions like "Executed ls command". Notes form the basis of the final answer.
    *   `analyze_code_question`: Usually only needed once at the start if the initial question is unclear (rarely needed in the loop).
    *   `finish`: Use **ONLY** when you are confident that the CURRENT NOTES contain enough information gathered through exploration to comprehensively answer the original USER QUESTION. Do not finish prematurely.

    === RESPONSE FORMATTING ===
    Respond ONLY with a valid JSON object adhering to the schema below.
    DO NOT include any other text, explanations, or markdown formatting (like ```json ... ```) outside of the JSON object itself.
    Your entire response must be ONLY the JSON object.
    --- SCHEMA START ---
    #{format_instructions}
    --- SCHEMA END ---
    PROMPT
  end

  def analyze_question_prompt(question:)
    <<~PROMPT
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
  end

  def search_examples_prompt(topic:, language: nil)
    language_str = language.present? ? " in #{language}" : ""
    code_lang = language || "code"

    <<~PROMPT
      Find code examples for the topic#{language_str}:

      TOPIC: #{topic}

      Provide:
      1. 2-3 realistic, well-commented code examples.
      2. Brief explanations for each.
      3. Common variations or alternatives.

      FORMAT:
      ## Example 1
      ```#{code_lang}
      [Code]
      ```
      **Explanation**: [Explanation]

      ## Example 2
      ...

      ## Common Variations
      [Variations]
    PROMPT
  end

  def explain_code_prompt(code:, language: nil)
    language_str = language.present? ? " (#{language})" : ""
    code_lang = language || "code"

    <<~PROMPT
      Provide a detailed explanation of the following code#{language_str}:

      ```#{code_lang}
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
  end

  def compile_findings_prompt(task_title:, formatted_notes:)
    <<~PROMPT
      # CODE RESEARCH SYNTHESIS TASK

      Synthesize these research notes into a comprehensive technical documentation about:
      TOPIC: "#{task_title}"

      # SOURCE NOTES
      #{formatted_notes}

      # EXPECTED OUTPUT FORMAT
      Create a professional technical document with these sections:

      ## 1. EXECUTIVE SUMMARY
      - Concise overview of findings (1-2 paragraphs)
      - Key insights and recommendations

      ## 2. CODEBASE ARCHITECTURE
      - Overall structure and organization
      - Key components and their relationships
      - Design patterns and architectural principles identified

      ## 3. IMPLEMENTATION DETAILS
      - Important classes, methods, and functions
      - Workflow and control flow
      - Notable algorithms or techniques

      ## 4. CODE QUALITY ASSESSMENT
      - Strengths of the implementation
      - Potential issues or improvement areas
      - Code smells or anti-patterns observed

      ## 5. RECOMMENDATIONS
      - Specific actionable recommendations
      - Refactoring opportunities
      - Best practices that could be applied

      Use clear, technical language with concrete examples from the codebase.
      Structure information hierarchically with proper markdown headings and formatting.
    PROMPT
  end
  end
end
