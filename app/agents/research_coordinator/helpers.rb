# frozen_string_literal: true

module ResearchCoordinator
  module Helpers
    # Helper method to determine appropriate researcher type
    def determine_researcher_type(methods)
      methods = Array(methods).map { |m| m.to_s.downcase }

      if methods.empty? || methods.any? { |m| m.include?("web") || m.include?("internet") }
        "WebResearcherAgent"
      elsif methods.any? { |m| m.include?("code") || m.include?("codebase") }
        "CodeResearcherAgent"
      elsif methods.any? { |m| m.include?("summarize") || m.include?("summary") }
        "SummarizerAgent"
      # Add more specific researcher types here based on methods if needed
      # elsif methods.include?("database")
      #   "DatabaseResearcherAgent"
      else
        # Default to web researcher if type cannot be determined
        Rails.logger.warn "[ResearchCoordinatorAgent] Could not determine specific researcher type for methods: #{methods}. Defaulting to WebResearcherAgent."
        "WebResearcherAgent"
      end
    end

    # Parse analysis to get subtask details
    def parse_research_subtasks(analysis)
      prompt_content = parse_research_subtasks_prompt(analysis)

      begin
        response = @llm.chat(messages: [ { role: "user", content: prompt_content } ])
        log_direct_llm_call(prompt_content, response)

        # Parse JSON from response
        json_string = response.chat_completion
        subtasks_data = JSON.parse(json_string)

        # Convert to expected format if needed
        subtasks_data.map do |subtask|
          {
            title: subtask["title"],
            description: subtask["description"],
            methods: subtask["methods"] || []
          }
        end
      rescue JSON::ParserError => e
        Rails.logger.error "[ResearchCoordinatorAgent] Failed to parse subtasks JSON: #{e.message}"
        # Return a default structure with error information
        [ {
          title: "Research Error",
          description: "Failed to parse research subtasks. Original analysis: #{analysis}",
          methods: [ "web" ]
        } ]
      rescue => e
        Rails.logger.error "[ResearchCoordinatorAgent] Error parsing research subtasks: #{e.message}"
        # Return a default structure with error information
        [ {
          title: "Research Error",
          description: "Error analyzing research question: #{e.message}. Original analysis: #{analysis}",
          methods: [ "web" ]
        } ]
      end
    end
  end
end
