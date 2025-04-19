# frozen_string_literal: true

require "langchain" # Ensure langchain is required
require_relative "../tools/shell_tool" # Ensure ShellTool is loaded

# CodeResearcherAgent: Specializes in researching and understanding code
# Used for finding code examples, patterns, and documentation
class CodeResearcherAgent < BaseAgent
  include EventSubscriber
  include CodeResearcher::Prompts
  include CodeResearcher::ToolImplementations
  include CodeResearcher::EventHandlers
  include CodeResearcher::Helpers

  MAX_ITERATIONS = 50 # Safety break for the autonomous loop
  MAX_CONSECUTIVE_TOOL_ERRORS = 3 # Safety break for tool errors

  # Define queue
  def self.queue_name
    :code_researcher
  end

  # Limit concurrency
  def self.concurrency_limit
    3
  end

  # Subscribe to relevant events
  subscribe_to "code_research_task", :handle_code_research_task
  subscribe_to "code_discovery", :handle_code_discovery
  subscribe_to "research_findings", :handle_research_findings

  # === Custom Tool Objects ===
  def self.custom_tool_objects
    # Make ShellTool available to this agent instance
    [ ShellTool.new ]
  end
  # === End Custom Tool Objects ===

  # --- Tools with Explicit Parameter Documentation ---
  tool :analyze_code_question, "Break down a code-related research question. Takes (question: <detailed question>)" do |question:|
    analyze_code_question(question)
  end

  tool :shell_command, "Execute a shell command (safely within allowed directories). Takes (command: <shell command>, working_directory: <optional path>)" do |command:, working_directory: nil|
    implement_shell_command(command: command, working_directory: working_directory)
  end

  tool :search_code_base, "Search the code base for code examples using ripgrep. Takes (query: <search pattern>)" do |query:|
    implement_search_code_base(query: query)
  end

  tool :examine_directory, "Examine a directory and generate a textual summary of its contents using the code2prompt tool. Takes (directory_path: <path to directory>)" do |directory_path:|
    implement_examine_directory(directory_path: directory_path)
  end

  tool :search_for_examples, "Search for code examples on a topic. Takes (topic: <search topic>, language: <optional programming language>)" do |topic:, language: nil|
    search_for_examples(topic, language)
  end

  tool :explain_code, "Explain how a piece of code works. Takes (code: <code snippet>, language: <optional programming language>)" do |code:, language: nil|
    explain_code(code, language)
  end

  tool :take_notes, "IMPORTANT: Document findings about the codebase. Use this after discoveries to build the final report. Each note should contain specific, detailed observations. Takes (note: <detailed observation>)" do |note:|
    take_notes(note)
  end

  tool :compile_findings, "Compile research notes into structured findings. Takes no parameters." do
    compile_findings
  end
  # --- End Tools ---

  # --- Core Logic ---
  def run(input = nil)
    before_run(input)
    question = input.present? ? input : "Error: No input provided."
    final_result_message = "Code research initiated for: #{question.truncate(100)}"

    unless task
      Rails.logger.warn "[CodeResearcherAgent] Running without an associated task record. Note-taking and compilation require a task."
      @session_data[:output] = "Error: Task required for autonomous research."
      after_run(@session_data[:output])
      return @session_data[:output]
    end

    # Parse input context if provided
    context = input.is_a?(Hash) ? input[:context] : nil
    event_type = context&.dig(:event_type)

    begin
      Rails.logger.info "[CodeResearcherAgent-#{task&.id}] Starting autonomous research loop for: #{question}"

      # Handle different event types or start autonomous research
      if event_type == "code_discovery"
        # Handle code discovery event
        discovery = context[:discovery]
        Rails.logger.info "[CodeResearcherAgent-#{task&.id}] Processing code discovery: #{discovery.truncate(100)}"
        execute_tool(:take_notes, note: "Code discovery from event: #{discovery}")
        final_result_message = "Processed code discovery and added to research notes."
      elsif event_type == "research_findings"
        # Handle research findings event
        findings = context[:findings]
        Rails.logger.info "[CodeResearcherAgent-#{task&.id}] Processing research findings: #{findings.truncate(100)}"
        task.update!(result: findings)
        task.complete! if task.may_complete?
        final_result_message = "Processed and saved research findings."
      else
        # Start autonomous research loop
        final_result_message = run_autonomous_research_loop(question)
      end

    rescue => e
      # Catch errors outside the main loop/ensure block (e.g., initial setup, parser init)
      final_result_message = "Agent run failed unexpectedly: #{e.message}"
      handle_run_error(e) # This should mark activity/task as failed
      # Ensure we don't mask the original error if handle_run_error raises something else
      raise e unless e.is_a?(StandardError) # Avoid re-raising non-standard errors if handle_run_error messes up
    end

    @session_data[:output] = final_result_message
    after_run(final_result_message)
    final_result_message
  end
  # --- End Core Logic ---

  private

  # Main autonomous research loop
  def run_autonomous_research_loop(question)
    # Define the JSON schema for the expected LLM response
    available_tool_names = @tools.flat_map do |tool_def|
      if tool_def.is_a?(Hash)
        tool_def[:name].to_s # Block tool
      elsif tool_def.class.respond_to?(:defined_functions)
        tool_def.class.defined_functions.keys.map(&:to_s) # Tool object functions
      else
        []
      end
    end.uniq + [ "finish" ]

    action_schema = {
      type: "object",
      properties: {
        action: {
          type: "string",
          description: "The name of the tool to use or 'finish'.",
          enum: available_tool_names
        },
        arguments: {
          type: "object",
          description: "A hash of arguments for the chosen tool (string keys and values). Empty if action is 'finish'. Arguments should be passed as keyword arguments.",
          additionalProperties: { type: "string" }
        }
      },
      required: [ "action", "arguments" ],
      additionalProperties: false
    }

    # Initialize the parser
    parser = Langchain::OutputParsers::StructuredOutputParser.from_json_schema(action_schema)

    iterations = 0
    consecutive_tool_errors = 0
    last_tool_result_text = "No tool executed yet." # Variable to hold the last result
    final_result_message = "Research completed successfully."

    # --- Main Autonomous Loop ---
    begin
      loop do
        iterations += 1
        if iterations > MAX_ITERATIONS
          Rails.logger.warn "[CodeResearcherAgent-#{task&.id}] Reached maximum iterations (#{MAX_ITERATIONS})."
          final_result_message = "Research stopped after reaching maximum iterations (#{MAX_ITERATIONS})."

          begin
            if agent_activity.present?
              agent_activity.events.create(event_type: "max_iterations_reached", data: { max: MAX_ITERATIONS })
              agent_activity.mark_failed(final_result_message)
            end
            task&.mark_failed(final_result_message)
          rescue => e
            Rails.logger.error "[CodeResearcherAgent-#{task&.id}] Error during failure handling: #{e.message}"
          end
          break # Exit Loop
        end

        if consecutive_tool_errors >= MAX_CONSECUTIVE_TOOL_ERRORS
          Rails.logger.error "[CodeResearcherAgent-#{task&.id}] Reached maximum consecutive tool errors (#{MAX_CONSECUTIVE_TOOL_ERRORS})."
          final_result_message = "Research stopped after #{MAX_CONSECUTIVE_TOOL_ERRORS} consecutive tool errors."

          begin
            if agent_activity.present?
              agent_activity.events.create(event_type: "max_consecutive_tool_errors_reached", data: { max: MAX_CONSECUTIVE_TOOL_ERRORS })
              agent_activity.mark_failed(final_result_message)
            end
            task&.mark_failed(final_result_message)
          rescue => e
            Rails.logger.error "[CodeResearcherAgent-#{task&.id}] Error during failure handling: #{e.message}"
          end
          break # Exit Loop
        end

        Rails.logger.info "[CodeResearcherAgent-#{task&.id}] Iteration #{iterations}/#{MAX_ITERATIONS}, Consecutive Errors: #{consecutive_tool_errors}"

        # 1. Get available tools formatted for LLM
        formatted_tools = format_tools_for_llm

        # 2. Get current notes (freshly read each iteration)
        current_notes = task.reload.metadata&.dig("research_notes")&.join("\n---\n") || "No notes taken yet."

        # --- Get History for Prompt ---
        examined_dirs_history = track_examined_directories
        previous_commands_history = track_previous_commands

        # --- Add Last Tool Result to Context ---
        # Truncate long results to keep prompt size manageable
        last_result_display = if last_tool_result_text.nil?
                                "No previous tool result."
        elsif last_tool_result_text.length > 1500 # Adjust truncation length as needed
                                last_tool_result_text.truncate(1500, omission: "... (result truncated)")
        else
                                last_tool_result_text
        end

        # 3. Construct prompt for LLM using format instructions from the parser
        format_instructions = parser.get_format_instructions
        prompt_content = main_loop_prompt(
          question: question,
          current_notes: current_notes,
          examined_dirs_history: examined_dirs_history,
          previous_commands_history: previous_commands_history,
          last_result_display: last_result_display,
          formatted_tools: formatted_tools,
          format_instructions: format_instructions,
          iterations: iterations,
          max_iterations: MAX_ITERATIONS
        )

        # 4. Call LLM
        Rails.logger.debug "[CodeResearcherAgent-#{task&.id}] Prompting LLM for next action (Iteration #{iterations})."
        llm_response = @llm.chat(messages: [ { role: "user", content: prompt_content } ])
        log_direct_llm_call(prompt_content, llm_response) # Log the call
        raw_llm_output = llm_response.chat_completion

        # 5. Parse LLM response using the StructuredOutputParser
        parsed_action_data = nil
        begin
          # --- Robust JSON Extraction ---
          json_string = nil
          # Find the first '{' and the last '}'
          start_index = raw_llm_output.index("{")
          end_index = raw_llm_output.rindex("}")

          if start_index && end_index && end_index > start_index
            json_string = raw_llm_output[start_index..end_index]
            Rails.logger.debug "[CodeResearcherAgent-#{task&.id}] Extracted potential JSON: #{json_string.inspect}"
            # Attempt to parse the extracted string
            parsed_action_data = parser.parse(json_string) # Returns a hash with string keys
          else
            # If no valid braces found, raise error before calling parser
            Rails.logger.error "[CodeResearcherAgent-#{task&.id}] Could not find valid JSON object markers '{' and '}' in LLM response."
            raise JSON::ParserError, "No JSON object found in response."
          end
          # --- End Robust JSON Extraction ---

        rescue JSON::ParserError => parsing_error
          Rails.logger.error "[CodeResearcherAgent-#{task&.id}] Failed to parse JSON from LLM response: #{parsing_error.message}"
          # Increment error counter for parsing failures too
          consecutive_tool_errors += 1 # Count parsing failure as an error step
          last_tool_result_text = "Error: Could not parse LLM action response (JSON::ParserError: #{parsing_error.message})."
          next # Skip to next iteration or break if max errors reached
        end

        # Validate parsed data structure
        unless parsed_action_data.is_a?(Hash) && parsed_action_data["action"].is_a?(String) && parsed_action_data["arguments"].is_a?(Hash)
          Rails.logger.error "[CodeResearcherAgent-#{task&.id}] Parsed action data has unexpected structure: #{parsed_action_data.inspect}"
          consecutive_tool_errors += 1
          last_tool_result_text = "Error: Parsed LLM action data had unexpected structure."
          next
        end

        # 6. Execute action or break loop
        action = parsed_action_data["action"]
        arguments = parsed_action_data["arguments"] || {} # Ensure arguments is a hash

        if action == "finish"
          Rails.logger.info "[CodeResearcherAgent-#{task&.id}] LLM decided to finish after #{iterations} iterations."
          final_result_message = "Research completed by LLM decision after #{iterations} iterations."
          break # Exit loop successfully
        else
          # Execute the chosen tool
          tool_name = action.to_sym
          Rails.logger.info "[CodeResearcherAgent-#{task&.id}] LLM chose tool: #{tool_name} with args: #{arguments.inspect}"

          # Symbolize keys for passing as keyword arguments to execute_tool -> tool block
          symbolized_args = arguments.transform_keys(&:to_sym)
          tool_result = nil
          begin
            # BaseAgent#execute_tool will find the tool block/method and execute it
            tool_result = if symbolized_args.empty?
                            execute_tool(tool_name) # Call tool without args
            else
                            # Call tool with keyword arguments
                            execute_tool(tool_name, **symbolized_args)
            end
            # Store result for the next iteration's prompt
            last_tool_result_text = tool_result.to_s
            consecutive_tool_errors = 0 # Reset error counter on success

          rescue ToolExecutionError => tool_error # Catch errors raised by tool blocks or execute_tool
            Rails.logger.error "[CodeResearcherAgent-#{task&.id}] ToolExecutionError executing tool '#{tool_name}': #{tool_error.message}"
            # Store error message for the next iteration's prompt
            last_tool_result_text = "Error executing tool '#{tool_name}': #{tool_error.message}"
            consecutive_tool_errors += 1
          rescue => other_error # Catch unexpected errors during tool execution
            Rails.logger.error "[CodeResearcherAgent-#{task&.id}] Unexpected error executing tool '#{tool_name}': #{other_error.message}"
            # Store error message for the next iteration's prompt
            last_tool_result_text = "Unexpected error executing tool '#{tool_name}': #{other_error.message}"
            consecutive_tool_errors += 1
          end
        end
      end # end loop
    ensure
      # --- Attempt Final Compilation ---
      # This runs regardless of how the loop exited (finish, max iterations, max errors)
      if task && task.reload.metadata&.dig("research_notes")&.any?
        begin
          Rails.logger.info "[CodeResearcherAgent-#{task&.id}] Attempting final compilation of findings..."
          # execute_tool will handle logging success/failure internally
          execute_tool(:compile_findings)
          Rails.logger.info "[CodeResearcherAgent-#{task&.id}] Final compilation attempt finished."
        rescue ToolExecutionError => compile_error
          # Log the error, but don't let it hide the original loop exit reason
          Rails.logger.error "[CodeResearcherAgent-#{task&.id}] Error during final compilation of findings: #{compile_error.message}"
          # Append to the existing message if one is set
          final_result_message = (final_result_message || "Research finished") + " (but failed to compile final findings: #{compile_error.message})"
        end
      else
        Rails.logger.info "[CodeResearcherAgent-#{task&.id}] No notes found to compile, or task missing."
      end
    end # --- End Main Autonomous Loop ---

    # Loop finished or broke. Final_result_message is set. Compilation attempted in ensure.
    Rails.logger.info "[CodeResearcherAgent-#{task&.id}] Autonomous loop processing finished. Final message: #{final_result_message}"

    # Mark task complete *only if* it didn't fail due to iterations/errors and wasn't already completed by compile_findings
    reloaded_task = task.reload
    if reloaded_task.state != "failed" && reloaded_task.state != "finished"
      reloaded_task.complete! if reloaded_task.may_complete?
      final_result_message ||= "Research completed without explicit finish action (check notes and logs)."
    elsif reloaded_task.state == "failed"
      final_result_message ||= "Research failed (check logs and compiled notes)."
    elsif reloaded_task.state == "finished"
      final_result_message ||= "Research finished and compiled successfully."
    end

    final_result_message
  end
end
