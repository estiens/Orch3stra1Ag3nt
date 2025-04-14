# frozen_string_literal: true

require "shellwords"
require "json"

module CodeResearcherToolImplementations
  # --- Tool Implementations ---
  # These methods are included in the CodeResearcherAgent

  # Implementations called directly by tool blocks
  def implement_shell_command(command:, working_directory: nil)
    shell_tool_instance = find_shell_tool
    result = shell_tool_instance.execute_shell(command: command, working_directory: working_directory)

    if result[:error]
      raise ToolExecutionError.new("ShellTool error: #{result[:error]}", tool_name: :shell_command)
    elsif result[:status] != 0
      Rails.logger.warn "[CodeResearcherAgent#shell_command] Command '#{command.truncate(50)}' exited with status #{result[:status]}. Stderr: #{result[:stderr]}"
    end

    result
  rescue => e
    raise e if e.is_a?(ToolExecutionError)
    raise ToolExecutionError.new("Internal error in shell_command tool: #{e.message}", tool_name: :shell_command, original_exception: e)
  end

  def implement_search_code_base(query:)
    shell_tool_instance = find_shell_tool
    safe_query = query.gsub("'", "'\\''") # Corrected escaping
    command = "rg --json '#{safe_query}'"
    result = shell_tool_instance.execute_shell(command: command)

    if result[:status] == 0 && result[:stdout].present?
      begin
        parsed_results = result[:stdout].lines.map { |line| JSON.parse(line.strip) }.reject(&:empty?)
        { status: "success", results: parsed_results }
      rescue JSON::ParserError => e
        Rails.logger.error "[CodeResearcherAgent] Failed to parse rg JSON output: #{e.message}. Raw: #{result[:stdout]}"
        raise ToolExecutionError.new("Search completed, but failed to parse rg JSON results: #{e.message}", tool_name: :search_code_base)
      end
    elsif result[:status] == 0
      { status: "success", results: [], message: "No matches found." }
    elsif result[:error]
      raise ToolExecutionError.new("ShellTool error during search: #{result[:error]}", tool_name: :search_code_base)
    else
      if result[:status] == 1
         { status: "success", results: [], message: "No matches found." }
      else
        raise ToolExecutionError.new("Search command failed with status #{result[:status]}. Stderr: #{result[:stderr]}", tool_name: :search_code_base)
      end
    end
  rescue => e
     raise e if e.is_a?(ToolExecutionError)
     raise ToolExecutionError.new("Internal error in search_code_base tool: #{e.message}", tool_name: :search_code_base, original_exception: e)
  end

  def implement_examine_directory(directory_path:)
    shell_tool_instance = find_shell_tool

    unless directory_path.is_a?(String) && !directory_path.strip.empty?
      raise ToolExecutionError.new("Invalid or empty directory_path provided.", tool_name: :examine_directory)
    end
    if directory_path.include?("..")
       raise ToolExecutionError.new("Directory path cannot contain '..'.", tool_name: :examine_directory)
    end

    absolute_path = File.expand_path(directory_path, Rails.root)
    unless File.directory?(absolute_path)
       raise ToolExecutionError.new("Provided path '#{directory_path}' is not a valid directory.", tool_name: :examine_directory)
    end

    safe_dir_path = Shellwords.escape(absolute_path)
    code2prompt_cmd = "/Users/estiens/code/ai/code2prompt/target/release/code2prompt #{safe_dir_path}"
    command = "#{code2prompt_cmd} && echo $(pbpaste)"
    result = shell_tool_instance.execute_shell(command: command)

    if result[:status] == 0
      { status: "success", summary: result[:stdout] }
    elsif result[:error]
      raise ToolExecutionError.new("ShellTool error examining directory: #{result[:error]}", tool_name: :examine_directory)
    else
      error_detail = result[:stderr].presence || "No detailed error output."
      raise ToolExecutionError.new("Command chain 'code2prompt && pbpaste' failed with status #{result[:status]}. Error: #{error_detail}", tool_name: :examine_directory)
    end

  rescue => e
    raise e if e.is_a?(ToolExecutionError)
    raise ToolExecutionError.new("Internal error in examine_directory tool: #{e.message}", tool_name: :examine_directory, original_exception: e)
  end

  def analyze_code_question(question)
    # Uses LLM directly
    prompt_content = analyze_question_prompt(question: question)
    begin
      response = @llm.chat(messages: [ { role: "user", content: prompt_content } ])
      log_direct_llm_call(prompt_content, response)
      response.chat_completion
    rescue => e
      raise ToolExecutionError.new("LLM Error analyzing code question: #{e.message}", tool_name: :analyze_code_question, original_exception: e)
    end
  end

  def search_for_examples(topic, language = nil)
    # Uses LLM directly
    prompt_content = search_examples_prompt(topic: topic, language: language)
    begin
      response = @llm.chat(messages: [ { role: "user", content: prompt_content } ])
      log_direct_llm_call(prompt_content, response)
      response.chat_completion
    rescue => e
      raise ToolExecutionError.new("LLM Error searching for code examples: #{e.message}", tool_name: :search_for_examples, original_exception: e)
    end
  end

  def explain_code(code, language = nil)
    # Uses LLM directly
    prompt_content = explain_code_prompt(code: code, language: language)
    begin
      response = @llm.chat(messages: [ { role: "user", content: prompt_content } ])
      log_direct_llm_call(prompt_content, response)
      response.chat_completion
    rescue => e
      raise ToolExecutionError.new("LLM Error explaining code: #{e.message}", tool_name: :explain_code, original_exception: e)
    end
  end

  # Reusing take_notes from WebResearcherAgent logic (can be extracted to a concern/module later)
  def take_notes(note) # Note: argument should be passed as `note:` by LLM
    unless task
      raise ToolExecutionError.new("Cannot take notes - Agent not associated with a task.", tool_name: :take_notes)
    end

    begin
      current_notes = task.metadata&.dig("research_notes") || []
      note_string = note.is_a?(String) ? note : note.to_s
      updated_notes = current_notes + [ note_string ]
      task.update!(metadata: (task.metadata || {}).merge({ "research_notes" => updated_notes }))

      "Code research note recorded: #{note_string.truncate(100)}"
    rescue => e
      Rails.logger.error "[CodeResearcherAgent] Error taking notes for task #{task.id}: #{e.message}"
      raise ToolExecutionError.new("Error recording note: #{e.message}", tool_name: :take_notes, original_exception: e)
    end
  end

  # Reusing compile_findings from WebResearcherAgent logic (can be extracted later)
  def compile_findings # No arguments expected
    unless task
      raise ToolExecutionError.new("Cannot compile findings - Agent not associated with a task.", tool_name: :compile_findings)
    end

    notes = task.metadata&.dig("research_notes") || []
    if notes.empty?
      return "No code research notes found to compile for task #{task.id}. Use take_notes tool first."
    end

    formatted_notes = notes.map.with_index { |note, i| "Note #{i + 1}:\n#{note}" }.join("\n\n---\n\n")
    prompt_content = compile_findings_prompt(task_title: task.title, formatted_notes: formatted_notes)

    begin
      # Use agent's LLM
      response = @llm.chat(messages: [ { role: "user", content: prompt_content } ])
      compiled_result = response.chat_completion

      # Manually log the LLM call
      log_direct_llm_call(prompt_content, response)

      # Store findings as the task result
      task.update!(result: compiled_result)
      task.complete! if task.may_complete?

      # Publish event if this is a subtask
      if task.parent_id
        Event.publish(
          "research_subtask_completed",
          { subtask_id: task.id, parent_id: task.parent_id, result: compiled_result },
          { agent_activity_id: agent_activity&.id }
        )
      end

      compiled_result
    rescue => e
      Rails.logger.error "[CodeResearcherAgent] LLM Error in compile_findings for task #{task.id}: #{e.message}"
      raise ToolExecutionError.new("Error compiling findings: #{e.message}", tool_name: :compile_findings, original_exception: e)
    end
  end
  # --- End Tool Implementations ---

  private

  # Helper to find the ShellTool instance within the agent's tools
  def find_shell_tool
    shell_tool = @tools.find { |t| t.is_a?(ShellTool) }
    raise "ShellTool instance not found in agent tools" unless shell_tool
    shell_tool
  end
end
