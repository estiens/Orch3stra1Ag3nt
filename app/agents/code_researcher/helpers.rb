# frozen_string_literal: true

module CodeResearcher
  module Helpers
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

    # Helper to find the ShellTool instance within the agent's tools
    def find_shell_tool
      shell_tool = @tools.find { |t| t.is_a?(ShellTool) }
      raise "ShellTool instance not found in agent tools" unless shell_tool
      shell_tool
    end
  end
end
