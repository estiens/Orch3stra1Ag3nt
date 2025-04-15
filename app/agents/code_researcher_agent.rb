# frozen_string_literal: true

require "langchain" # Ensure langchain is required
require_relative "../tools/shell_tool" # Ensure ShellTool is loaded
require_relative "code_researcher/prompts" # Load the prompts module
require_relative "code_researcher/tool_implementations" # Load tool implementations

# CodeResearcherAgent: Specializes in researching and understanding code
# Used for finding code examples, patterns, and documentation
class CodeResearcherAgent < BaseAgent
  include CodeResearcherPrompts # Include the prompts
  include CodeResearcherToolImplementations # Include the tool implementations

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

  # === Custom Tool Objects ===
  def self.custom_tool_objects
    # Make ShellTool available to this agent instance
    [ ShellTool.new ]
  end
  # === End Custom Tool Objects ===

  # --- Tools ---
  tool :analyze_code_question, "Break down a code-related research question" do |question:| # Added colon for kwarg consistency
    analyze_code_question(question)
  end

  tool :shell_command, "Execute a shell command (safely within allowed directories)" do |command:, working_directory: nil|
    implement_shell_command(command: command, working_directory: working_directory)
  end

  tool :search_code_base, "Search the code base for code examples using ripgrep (takes 'query: <your query here>') " do |query:| # Added colon
    implement_search_code_base(query: query)
  end

  tool :examine_directory, "Examine a directory and generate a textual summary of its contents using the code2prompt tool. Takes 'directory_path: <path to directory>'." do |directory_path:|
    implement_examine_directory(directory_path: directory_path)
  end

  tool :search_for_examples, "Search for code examples on a topic" do |topic:, language: nil| # Added colons
    search_for_examples(topic, language)
  end

  tool :explain_code, "Explain how a piece of code works" do |code:, language: nil| # Added colons
    explain_code(code, language)
  end

  tool :take_notes, "IMPORTANT: Document findings about the codebase. Use this after discoveries to build the final report. Each note should contain specific, detailed observations. Pass (note: <note)" do |note:|
    take_notes(note)
  end

  tool :compile_findings, "Compile research notes into structured findings" do
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

    begin
      Rails.logger.info "[CodeResearcherAgent-#{task&.id}] Starting autonomous research loop for: #{question}"

      # Define the JSON schema for the expected LLM response
      # Regenerate tool list to include tools from ShellTool if BaseAgent doesn't merge them automatically
      # NOTE: Assuming BaseAgent's @tools includes tools from custom_tool_objects correctly.
      # If not, BaseAgent initialization or find_tool_definition needs adjustment.
      available_tool_names = @tools.flat_map do |tool_def|
        if tool_def.is_a?(Hash)
           tool_def[:name].to_s # Block tool
        elsif tool_def.class.respond_to?(:defined_functions)
           tool_def.class.defined_functions.keys.map(&:to_s) # Tool object functions (e.g., execute_shell)
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
            # enum: (tools.map { |t| t.is_a?(Hash) ? t[:name].to_s : t.name.to_s } + [ "finish" ]) # Old way
            enum: available_tool_names # Use dynamically generated list
          },
          arguments: {
            type: "object",
            description: "A hash of arguments for the chosen tool (string keys and values). Empty if action is 'finish'. Arguments should be passed as keyword arguments.",
            # Ensure keys match expected tool parameters (e.g., 'command', 'query', 'file_path')
            additionalProperties: { type: "string" } # Allow any string arguments for tools
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

      # --- Main Autonomous Loop ---
      begin
        loop do
          iterations += 1
          if iterations > MAX_ITERATIONS
            Rails.logger.warn "[CodeResearcherAgent-#{task&.id}] Reached maximum iterations (#{MAX_ITERATIONS}). Research stopped. Consider refining the question or increasing MAX_ITERATIONS."
            final_result_message = "Research stopped after reaching maximum iterations (#{MAX_ITERATIONS}). Review logs (Activity ID: #{agent_activity&.id}) and compiled notes."

            # Safely create events and handle failures
            begin
              if agent_activity.present?
                agent_activity.events.create(event_type: "max_iterations_reached", data: { max: MAX_ITERATIONS })
                agent_activity.mark_failed(final_result_message)
              else
                Rails.logger.warn "[CodeResearcherAgent-#{task&.id}] Cannot create event or mark failed: No agent_activity associated"
              end

              task&.mark_failed(final_result_message) # Mark task failed with informative message
            rescue => e
              Rails.logger.error "[CodeResearcherAgent-#{task&.id}] Error during failure handling: #{e.message}"
            end
            break # Exit Loop
          end

          if consecutive_tool_errors >= MAX_CONSECUTIVE_TOOL_ERRORS
            Rails.logger.error "[CodeResearcherAgent-#{task&.id}] Reached maximum consecutive tool errors (#{MAX_CONSECUTIVE_TOOL_ERRORS}). Research stopped. Check tool implementation or LLM ability to use tools correctly."
            final_result_message = "Research stopped after #{MAX_CONSECUTIVE_TOOL_ERRORS} consecutive tool errors. Review logs (Activity ID: #{agent_activity&.id}) and compiled notes."

            # Safely create events and handle failures
            begin
              if agent_activity.present?
                agent_activity.events.create(event_type: "max_consecutive_tool_errors_reached", data: { max: MAX_CONSECUTIVE_TOOL_ERRORS })
                agent_activity.mark_failed(final_result_message)
              else
                Rails.logger.warn "[CodeResearcherAgent-#{task&.id}] Cannot create event or mark failed: No agent_activity associated"
              end

              task&.mark_failed(final_result_message) # Mark task failed with informative message
            rescue => e
              Rails.logger.error "[CodeResearcherAgent-#{task&.id}] Error during failure handling: #{e.message}"
            end

            break # Exit Loop
          end

          Rails.logger.info "[CodeResearcherAgent-#{task&.id}] Iteration #{iterations}/#{MAX_ITERATIONS}, Consecutive Errors: #{consecutive_tool_errors}"

          # 1. Get available tools formatted for LLM
          formatted_tools = format_tools_for_llm

          # 2. Get current notes (freshly read each iteration)
          # Use reload to ensure we have the latest metadata if notes were just taken
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
          Rails.logger.debug "[CodeResearcherAgent-#{task&.id}] Prompting LLM for next action (Iteration #{iterations}). Prompt length: #{prompt_content.length}"
          llm_response = @llm.chat(messages: [ { role: "user", content: prompt_content } ])
          log_direct_llm_call(prompt_content, llm_response) # Log the call
          raw_llm_output = llm_response.chat_completion

          # 5. Parse LLM response using the StructuredOutputParser
          parsed_action_data = nil
          begin
            # Add debugging for raw output before parsing
            Rails.logger.debug "[CodeResearcherAgent-#{task&.id}] Raw LLM output for parsing: #{raw_llm_output.inspect}"

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
              Rails.logger.error "[CodeResearcherAgent-#{task&.id}] Could not find valid JSON object markers '{' and '}' in LLM response. Raw: #{raw_llm_output.inspect}"
              raise JSON::ParserError, "No JSON object found in response."
            end
            # --- End Robust JSON Extraction ---

            # Add debugging for parsed output
            Rails.logger.debug "[CodeResearcherAgent-#{task&.id}] Parsed action data: #{parsed_action_data.inspect}"

          rescue JSON::ParserError => parsing_error
            Rails.logger.error "[CodeResearcherAgent-#{task&.id}] Failed to parse JSON from LLM response. Error: #{parsing_error.class} - #{parsing_error.message}. Raw LLM Output: #{raw_llm_output.inspect}. Extracted String: #{json_string.inspect}"
            # Increment error counter for parsing failures too
            consecutive_tool_errors += 1 # Count parsing failure as an error step
            last_tool_result_text = "Error: Could not parse LLM action response (JSON::ParserError: #{parsing_error.message})."
            # Don't mark task as failed yet, let the loop check consecutive errors
            next # Skip to next iteration or break if max errors reached
          end

          # Validate parsed data structure (OutputFixingParser should handle schema, but belts and suspenders)
          unless parsed_action_data.is_a?(Hash) && parsed_action_data["action"].is_a?(String) && parsed_action_data["arguments"].is_a?(Hash)
             Rails.logger.error "[CodeResearcherAgent-#{task&.id}] Parsed action data has unexpected structure: #{parsed_action_data.inspect}. Raw: #{raw_llm_output}"
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
              Rails.logger.error "[CodeResearcherAgent-#{task&.id}] ToolExecutionError executing tool '#{tool_name}' during loop: #{tool_error.message}"
              # Store error message for the next iteration's prompt
              last_tool_result_text = "Error executing tool '#{tool_name}': #{tool_error.message}"
              consecutive_tool_errors += 1
              # Optional: Log the error as a note?
              # execute_tool(:take_notes, note: "Error executing tool #{tool_name} (Iteration #{iterations}): #{tool_error.message}")
            rescue => other_error # Catch unexpected errors during tool execution
               Rails.logger.error "[CodeResearcherAgent-#{task&.id}] Unexpected error executing tool '#{tool_name}' during loop: #{other_error.message}\n#{other_error.backtrace.first(5).join("\n")}"
               # Store error message for the next iteration's prompt
               last_tool_result_text = "Unexpected error executing tool '#{tool_name}': #{other_error.message}"
               consecutive_tool_errors += 1
              # Treat unexpected errors similarly to ToolExecutionError for loop control
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
             # If compilation succeeded, the task result should be updated.
             # We don't necessarily need to override final_result_message here,
             # as the original reason for stopping (e.g., max iterations) is often more relevant.
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

    rescue => e
      # Catch errors outside the main loop/ensure block (e.g., initial setup, parser init)
      final_result_message = "Agent run failed unexpectedly before or after the main loop: #{e.message}"
      handle_run_error(e) # This should mark activity/task as failed
      # Ensure we don't mask the original error if handle_run_error raises something else
      raise e unless e.is_a?(StandardError) # Avoid re-raising non-standard errors if handle_run_error messes up
    end

    @session_data[:output] = final_result_message
    after_run(final_result_message)
    final_result_message
  end
  # --- End Core Logic ---

  # --- Tool Implementations ---
  # Removed implementations - now in CodeResearcherToolImplementations module
  # --- End Tool Implementations ---

  # --- Helper Methods ---
  private

  # Extracts a specific argument value from the stringified args hash stored in events
  # Note: This relies on the inspect format and might be fragile.
  # Better solution: Store args as structured JSON in the Event model.
  def extract_arg_value(args_string, key_symbol)
    return nil unless args_string.is_a?(String)
    # Regex to find the value associated with the symbol key (e.g., :command=>"value" or :key=>value)
    match = args_string.match(/#{key_symbol.inspect}\s*=>\s*(?:\"(.*?)\"|([^,\s}\]]+))/) # Handles quoted/unquoted values
    match ? (match[1] || match[2]) : nil
  end

  # Track directories previously examined via the examine_directory tool
  def track_examined_directories
    return "Error: Task not available for tracking" unless @task
    dirs = @task.agent_activities.flat_map do |activity|
      activity.events.where(event_type: "tool_execution_finished")
            .where("data::jsonb->>'tool' = ?", "examine_directory") # Cast to jsonb
            .map { |event| extract_arg_value(event.data["args"], :directory_path) }
    end.compact.uniq

    dirs.empty? ? "- None yet" : "- " + dirs.join("\n- ")
  end

  # Track shell commands previously run via the shell_command tool
  def track_previous_commands
    return "Error: Task not available for tracking" unless @task
    # Get the last 10 unique commands
    cmds = @task.agent_activities.flat_map do |activity|
      activity.events.where(event_type: "tool_execution_finished")
            .where("data::jsonb->>'tool' = ?", "shell_command") # Cast to jsonb
            .map { |event| extract_arg_value(event.data["args"], :command) } # Use event.data["args"]
    end.compact.uniq.last(10)

    cmds.empty? ? "- None yet" : "- " + cmds.join("\n- ")
  end

  def format_tools_for_llm
    # Regenerate tool descriptions including those from Tool Objects like ShellTool
    @tools.flat_map do |tool_def|
      if tool_def.is_a?(Hash) && tool_def[:name] && tool_def[:description]
        # Format block tool
        "- #{tool_def[:name]}: #{tool_def[:description]}"
      elsif tool_def.class.respond_to?(:defined_functions)
         # Format functions from Tool Object
         tool_def.class.defined_functions.map do |func_name, definition|
           # Include parameter details for better LLM guidance
           params_desc = definition[:parameters][:properties].map do |p_name, p_def|
             req = definition[:parameters][:required]&.include?(p_name.to_s) ? " (required)" : ""
             "#{p_name} (#{p_def[:type]})#{req}: #{p_def[:description]}"
           end.join("; ")
           "- #{func_name}: #{definition[:description]} | Params: #{params_desc}"
         end
      else
        nil # Skip malformed tool definitions
      end
    end.compact.join("\n")
  end

  # Removed parse_llm_tool_response as it's replaced by the langchain parser
end
