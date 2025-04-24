# frozen_string_literal: true

module Coordinator
  module Helpers
    # Parses LLM output to extract structured subtask information
    # Returns dependency indices and complexity
    def parse_subtasks_from_llm(llm_output)
      subtasks = []

      # Split by common subtask separator patterns
      sections = llm_output.split(/---|\*{3}|={3}|Subtask\s+\d+:/).reject(&:empty?)

      # If we don't find sections with the splitter, try another approach
      if sections.size <= 1
        # Try parsing with the numbered subtask format
        sections = llm_output.scan(/Subtask\s+\d+:.*?(?=Subtask\s+\d+:|$)/m)
      end

      # Process each section
      sections.each do |section|
        # Extract basic components with less complex patterns
        title_match = section.match(/(?:Subtask\s+\d+:)?\s*(.*?)(?:\r?\n|\n|$)/)
        description_match = section.match(/Description:?\s*(.*?)(?:Priority:|Agent:|Dependencies:|Complexity:|$)/m)
        priority_match = section.match(/Priority:?\s*([Hh]igh|[Nn]ormal|[Ll]ow)/)
        agent_match = section.match(/Agent:?\s*([A-Za-z]+Agent)/)
        deps_match = section.match(/Dependencies:?\s*(None|(?:\d+(?:,\s*\d+)*))/)
        complexity_match = section.match(/Complexity:?\s*([Ss]imple|[Mm]oderate|[Cc]omplex)/)

        # Skip if we can't extract the minimum required information
        next unless title_match && description_match && priority_match

        title = title_match[1].strip
        description = description_match[1].strip
        priority = priority_match[1].downcase.strip
        agent_type = agent_match ? agent_match[1].strip : "ResearcherAgent"

        # If complexity is "complex", suggest CoordinatorAgent
        complexity = complexity_match ? complexity_match[1].downcase.strip : "simple"
        if complexity == "complex" && agent_type != "CoordinatorAgent"
          agent_type = "CoordinatorAgent"
        end

        # Parse dependencies
        deps_str = deps_match ? deps_match[1].strip : "None"
        dependency_indices = deps_str.downcase == "none" ? [] : deps_str.split(/,\s*/).map(&:to_i)

        # Don't add if title is empty or just whitespace
        next if title.empty?

        subtasks << {
          title: title,
          description: description,
          priority: priority,
          agent_type: agent_type,
          dependencies: dependency_indices,
          complexity: complexity
        }
      end

      Rails.logger.info "[CoordinatorAgent] Parsed #{subtasks.count} subtasks from analysis"

      # Return early if we found subtasks
      return subtasks unless subtasks.empty?

      # Last resort: try a very simple pattern matching approach for each subtask
      begin
        # Look for potential subtask titles
        potential_titles = llm_output.scan(/(?:^|\n)(?:Subtask\s+\d+:)?\s*([A-Z][\w\s,]+)(?:\n|$)/)

        potential_titles.each_with_index do |title_match, index|
          title = title_match[0].strip
          # Get the section following this title (until the next potential title or end)
          next_title_pos = llm_output.index(potential_titles[index + 1]&.[](0)) if index + 1 < potential_titles.size
          section = next_title_pos ? llm_output[llm_output.index(title)...next_title_pos] : llm_output[llm_output.index(title)..-1]

          # Try to extract description and priority
          desc_text = section.match(/(?:Description:?\s*)(.*?)(?:Priority:|Agent:|Dependencies:|$)/m)&.[](1)&.strip
          priority_text = section.match(/Priority:?\s*([Hh]igh|[Nn]ormal|[Ll]ow)/)&.[](1)&.downcase

          next unless desc_text && priority_text

          subtasks << {
            title: title,
            description: desc_text,
            priority: priority_text,
            agent_type: "ResearcherAgent", # Default
            dependencies: []  # Default empty
          }
        end
      rescue => parsing_error
        Rails.logger.error "[CoordinatorAgent] Error in fallback parsing: #{parsing_error.message}"
      end

      Rails.logger.info "[CoordinatorAgent] Final parsed subtask count: #{subtasks.count}"
      subtasks
    rescue => e
      Rails.logger.error "[CoordinatorAgent] Failed to parse subtasks: #{e.message}"
      Rails.logger.error "LLM Output (first 500 chars): #{llm_output[0..500]}"
      []
    end

    # Find pending subtasks whose dependencies are met
    def find_eligible_pending_subtasks
      pending_subtasks = task.subtasks.where(state: "pending")
      return [] if pending_subtasks.empty?

      # Check if dependencies are satisfied using the method we added to Task
      pending_subtasks.select(&:dependencies_satisfied?)
    end

    # Select the next subtask to assign from a list of eligible ones
    def select_next_subtask_to_assign(eligible_subtasks)
      # Prioritize by 'priority' field (high > normal > low), then by creation date (oldest first)
      priority_order = { "high" => 0, "normal" => 1, "low" => 2 }
      eligible_subtasks.min_by { |s| [ priority_order[s.priority] || 99, s.created_at.to_i ] }
    end

    # Determine the best agent type for a subtask (fallback if not suggested)
    def determine_best_agent_for_subtask(subtask)
      # First check if the subtask already has a predetermined agent type
      if subtask.metadata&.dig("agent_type")
        return subtask.metadata["agent_type"]
      end

      # Use stored agent recommendation from task decomposition if available
      if subtask.metadata&.dig("suggested_agent")
        return subtask.metadata["suggested_agent"]
      end

      # Check if complexity is stored in metadata and is "complex"
      if subtask.metadata&.dig("complexity") == "complex"
        return "CoordinatorAgent"
      end

      # Otherwise, analyze the subtask description to suggest an appropriate agent
      prompt = <<~PROMPT
        # AGENT SELECTION

        Based on this subtask description, determine the SINGLE most appropriate agent type:

        ## SUBTASK
        Title: #{subtask.title}
        Description: #{subtask.description}

        ## AVAILABLE AGENT TYPES
        - ResearcherAgent: General research and information gathering
        - WebResearcherAgent: Web browsing and internet research
        - CodeResearcherAgent: Code analysis and programming tasks
        - WriterAgent: Content creation and documentation
        - AnalyzerAgent: Data analysis and insight generation
        - CoordinatorAgent: For complex subtasks that need further decomposition into smaller tasks

        ## ASSESSMENT CRITERIA
        - Choose CoordinatorAgent if the subtask is complex and would benefit from being broken down into multiple smaller subtasks
        - Prefer CoordinatorAgent for any task that involves multiple distinct steps or requires different skills
        - For simple, focused tasks, choose one of the specialized agents

        ## REQUIRED OUTPUT FORMAT
        RECOMMENDED AGENT: [Single agent type from the list above]
        REASON: [Brief justification]
      PROMPT

      begin
        response = @llm.chat(messages: [ { role: "user", content: prompt } ])
        log_direct_llm_call(prompt, response)
        analysis = response.chat_completion
        if analysis =~ /RECOMMENDED AGENT:\s*([A-Za-z]+Agent)/
          $1
        else
          "ResearcherAgent"
        end
      rescue => e
        Rails.logger.error "[CoordinatorAgent] Error determining agent type: #{e.message}"
        "ResearcherAgent" # Safe fallback
      end
    end

    # Helper method to sort subtasks by priority and complexity
    def sort_subtasks_by_priority_and_complexity(subtasks)
      # Priority order: high > normal > low
      priority_order = { "high" => 0, "normal" => 1, "low" => 2 }

      # Complexity order: simple > moderate > complex
      complexity_order = { "simple" => 0, "moderate" => 1, "complex" => 2 }

      subtasks.sort_by do |subtask|
        priority = subtask.priority || "normal"
        complexity = subtask.metadata&.dig("complexity") || "simple"

        # Sort first by priority, then by complexity (simpler first)
        [ priority_order[priority] || 99, complexity_order[complexity] || 99 ]
      end
    end

    # Handle a failed subtask with recovery options
    def handle_failed_subtask(subtask_id, error)
      subtask = task.subtasks.find_by(id: subtask_id)
      return "Error: Failed subtask #{subtask_id} not found" unless subtask

      Rails.logger.info "[CoordinatorAgent-#{task.id}] Handling failed subtask #{subtask_id}: #{subtask.title}"

      # Log the failure
      update_task_status("Subtask #{subtask_id} (#{subtask.title}) failed: #{error}")

      # Analyze failure using LLM to determine recovery strategy
      prompt = <<~PROMPT
        # SUBTASK FAILURE ANALYSIS

        A subtask has failed and requires intelligent handling. Analyze the failure and recommend ONE of the following actions:
        1. RETRY - The subtask can be attempted again with the same parameters
        2. REDEFINE - The subtask needs to be redefined with different parameters
        3. SPLIT - The subtask should be split into smaller, more manageable subtasks
        4. HUMAN - Human intervention is required to proceed
        5. SKIP - The subtask can be skipped without affecting the overall task

        ## FAILED SUBTASK
        ID: #{subtask_id}
        Title: #{subtask.title}
        Description: #{subtask.description}
        Assigned Agent: #{subtask.metadata&.dig("assigned_agent") || "Unknown"}

        ## ERROR DETAILS
        #{error}

        ## PARENT TASK CONTEXT
        Task: #{task.title}
        Description: #{task.description}

        ## RECOMMENDATION FORMAT
        ACTION: [ONE of: RETRY, REDEFINE, SPLIT, HUMAN, SKIP]
        REASON: [Brief explanation of your recommendation]
        DETAILS: [Any specific details needed to implement your recommendation]
      PROMPT

      begin
        response = @llm.chat(messages: [ { role: "user", content: prompt } ])
        log_direct_llm_call(prompt, response)
        analysis = response.chat_completion

        # Parse LLM response to get recommended action
        if analysis.include?("ACTION: RETRY")
          # Attempt to reassign the same subtask
          subtask.update(state: "pending")
          assign_subtask(subtask_id, subtask.metadata&.dig("assigned_agent") || "ResearcherAgent", "Retry after failure: #{error}")
        elsif analysis.include?("ACTION: REDEFINE")
          # Create a new improved version of the subtask
          description = "REDEFINED AFTER FAILURE: #{subtask.description}\n\nPrevious Error: #{error}"
          new_subtask = create_subtask("Redefined: #{subtask.title}", description, subtask.priority)
          # Extract subtask ID from result
          new_id = new_subtask.match(/ID: (\d+)/)[1] rescue nil
          if new_id
            assign_subtask(new_id, subtask.metadata&.dig("assigned_agent") || "ResearcherAgent", "Redefined after failure")
          else
            "Created redefined subtask, but failed to extract ID for assignment: #{new_subtask}"
          end
        elsif analysis.include?("ACTION: SPLIT")
          # Request a decomposition of the failed subtask
          "Initiating decomposition of failed subtask. Marking original as canceled."
        elsif analysis.include?("ACTION: HUMAN")
          # Request human intervention
          request_human_input("Subtask #{subtask_id} (#{subtask.title}) failed and requires human intervention: #{error}", true)
        elsif analysis.include?("ACTION: SKIP")
          # Mark as successful with explanation
          subtask.update(state: "completed", result: "Skipped due to non-critical failure: #{error}")
          "Marked subtask #{subtask_id} as completed (skipped) as it was deemed non-critical."
        else
          # Default to human intervention if analysis is unclear
          request_human_input("Subtask #{subtask_id} failed and automatic recovery is unclear. Please review: #{error}", false)
        end
      rescue => e
        Rails.logger.error "[CoordinatorAgent] Error analyzing failed subtask: #{e.message}"
        request_human_input("Error analyzing failed subtask #{subtask_id}: #{e.message}. Original error: #{error}", true)
      end
    end

    # Process a completed subtask and determine next steps
    def process_completed_subtask(subtask_id, result)
      task.reload

      # Get the completed subtask
      subtask = Task.find_by(id: subtask_id)
      return "Error: Completed subtask #{subtask_id} not found" unless subtask

      # Check if this was a subtask handled by a sub-coordinator
      was_sub_coordinated = subtask.metadata&.dig("assigned_agent") == "CoordinatorAgent"
      nesting_level = subtask.metadata&.dig("nesting_level") || 0

      # Log completion with appropriate context
      if was_sub_coordinated
        update_task_status("Subtask #{subtask_id} (#{subtask.title}) completed by sub-coordinator (level #{nesting_level}).")
      else
        update_task_status("Subtask #{subtask_id} (#{subtask.title}) completed successfully.")
      end

      # Check overall task progress
      status_report = check_subtasks

      # If all subtasks are complete, finalize the task
      if task.subtasks.all? { |s| s.state == "completed" }
        return mark_task_complete # This will generate the final summary
      end

      # Find and assign the next *eligible* subtask
      eligible_subtasks = find_eligible_pending_subtasks
      if eligible_subtasks.any?
        # Assign multiple eligible subtasks in parallel if possible
        # This is a key improvement - we'll try to assign up to 3 subtasks at once
        assigned_count = 0
        assignment_results = []

        # Sort eligible subtasks by priority and then by complexity (simpler first)
        sorted_subtasks = sort_subtasks_by_priority_and_complexity(eligible_subtasks)

        # Try to assign up to 3 subtasks (or fewer if there aren't that many)
        sorted_subtasks.first(3).each do |next_subtask|
          # Skip if we've already assigned 3 subtasks
          break if assigned_count >= 3

          # Determine if this subtask needs a sub-coordinator or a regular agent
          agent_type = next_subtask.metadata&.dig("suggested_agent") || determine_best_agent_for_subtask(next_subtask)
          complexity = next_subtask.metadata&.dig("complexity") || "simple"

          # If complex or explicitly a CoordinatorAgent, use create_sub_coordinator
          if agent_type == "CoordinatorAgent" || complexity == "complex"
            assign_result = create_sub_coordinator(next_subtask.id, "Complex subtask requiring further decomposition")
          else
            assign_result = assign_subtask(next_subtask.id, agent_type, "Assigning eligible subtask in parallel")
          end

          assignment_results << assign_result
          assigned_count += 1
        end

        if assigned_count > 0
          return "#{status_report}\n\nAssigned #{assigned_count} eligible subtasks in parallel:\n\n#{assignment_results.join("\n\n")}"
        end
      end

      # Return comprehensive status if no immediate action needed
      active_count = task.subtasks.where(state: "active").count
      "#{status_report}\n\nContinuing to monitor #{active_count} active subtasks. No new subtasks are eligible for assignment yet."
    end

    # Handle human input requirement
    def handle_human_input_requirement(question)
      task.reload

      # Check if there are eligible pending subtasks that can proceed in parallel
      eligible_subtasks = find_eligible_pending_subtasks

      if eligible_subtasks.any?
        # We can still make progress on other subtasks while waiting
        status = "Working on parallel subtasks while waiting for human input: '#{question}'"
        update_task_status(status)

        # Find and assign an eligible subtask we can work on
        next_subtask = select_next_subtask_to_assign(eligible_subtasks)
        agent_type = next_subtask.metadata&.dig("suggested_agent") || determine_best_agent_for_subtask(next_subtask)
        assign_result = assign_subtask(next_subtask.id, agent_type, "Parallel work while waiting for human input")

        "#{status}\\n\\n#{assign_result}"
      else
        # Nothing else to do but wait
        active_count = task.subtasks.where(state: "active").count
        "Task is waiting for human input on question: '#{question}'. #{active_count} subtasks still active. No parallel work available."
      end
    end

    # Perform initial task decomposition
    def perform_initial_task_decomposition
      Rails.logger.info "[CoordinatorAgent-#{task.id}] Performing initial task decomposition for: #{task.title}"

      # Analyze the task
      analysis_result = execute_tool(:analyze_task, task_description: task.description)

      # Parse subtasks from the analysis, including dependency indices
      subtasks_data = parse_subtasks_from_llm(analysis_result) # Ensure this returns dependency indices

      if subtasks_data.empty?
        Rails.logger.warn "[CoordinatorAgent-#{task.id}] Analysis did not yield any subtasks."
        return "Task analysis complete, but no subtasks were identified. This may indicate the task is too simple for decomposition or the analysis failed."
      end

      # Record the decomposition strategy
      update_task_status("Task decomposed into #{subtasks_data.count} subtasks: #{subtasks_data.map { |s| s[:title] }.join(', ')}")

      # --- Create all subtasks first ---
      created_subtasks_map = {} # Map original index to created subtask object
      subtasks_data.each_with_index do |subtask_info, index|
        # Create subtask but don't assign yet
        create_result = execute_tool(:create_subtask,
                             title: subtask_info[:title],
                             description: subtask_info[:description],
                             priority: subtask_info[:priority])
        # Extract ID (assuming result format is like "Created subtask '...' (ID: 123, ...)")
        subtask_id = create_result.match(/ID: (\d+)/)&.[](1)&.to_i
        if subtask_id
          subtask = Task.find(subtask_id)
          # Store suggested agent type, complexity, and original index in metadata for later use
          subtask.update!(metadata: subtask.metadata.merge({
            suggested_agent: subtask_info[:agent_type],
            complexity: subtask_info[:complexity] || "simple",
            original_index: index + 1
          }))
          created_subtasks_map[index + 1] = subtask # Map original index to subtask
        else
          Rails.logger.error "[CoordinatorAgent-#{task.id}] Failed to extract subtask ID from create result: #{create_result}"
          # Handle error - maybe request human input?
          request_human_input("Failed to create or parse subtask '#{subtask_info[:title]}'. Please review decomposition.", true)
          return "Error during subtask creation. Human input requested."
        end
      end

      # --- Now update dependencies ---
      created_subtasks_map.each do |original_index, subtask|
        # Find original dependency indices for this subtask
        dependency_indices = subtasks_data[original_index - 1][:dependencies] # Get indices from original data

        # Map indices to actual Task IDs
        dependency_ids = dependency_indices.map { |idx| created_subtasks_map[idx]&.id }.compact

        # Update the subtask record
        subtask.update!(depends_on_task_ids: dependency_ids) unless dependency_ids.empty?
      end

      # --- Assign initially eligible subtasks ---
      eligible_subtasks = find_eligible_pending_subtasks
      assigned_count = 0
      if eligible_subtasks.any?
        # Assign potentially multiple initially eligible tasks (those with no deps)
        eligible_subtasks.each do |subtask_to_assign|
           agent_type = subtask_to_assign.metadata&.dig("suggested_agent") || determine_best_agent_for_subtask(subtask_to_assign)

           # If the LLM suggested a CoordinatorAgent, use create_sub_coordinator instead of assign_subtask
           if agent_type == "CoordinatorAgent"
             create_sub_coordinator(subtask_to_assign.id, "Complex subtask requiring further decomposition")
           else
             assign_subtask(subtask_to_assign.id, agent_type, "Assigning initial eligible subtask")
           end
           assigned_count += 1
        end
        "Task successfully decomposed into #{subtasks_data.count} subtasks. " +
        "#{assigned_count} initially eligible subtasks have been assigned. " +
        "Remaining subtasks will be assigned as dependencies are satisfied."
      else
        "Task successfully decomposed into #{subtasks_data.count} subtasks. " +
        "No subtasks are immediately eligible for assignment (check dependencies)."
      end
    end

    # Evaluate current task progress and determine next actions
    def evaluate_current_progress
      task.reload

      # Get comprehensive status report
      status_report = check_subtasks

      # Check if task is already completed
      if task.state == "completed"
        return "Task #{task.id} is already completed."
      end

      # Check if all subtasks are completed but task isn't marked complete
      if task.subtasks.any? && task.subtasks.all? { |s| s.state == "completed" }
        completion_result = mark_task_complete
        return "#{status_report}\\n\\n#{completion_result}"
      end

      # Check for failed subtasks (should trigger handle_failed_subtask via events, but double-check)
      failed_subtasks = task.subtasks.where(state: "failed")
      if failed_subtasks.any?
        failed_ids = failed_subtasks.pluck(:id).join(", ")
        # Consider triggering failure handling if event missed?
        return "#{status_report}\\n\\nATTENTION REQUIRED: Found #{failed_subtasks.count} failed subtasks: #{failed_ids}. Failure handling should be initiated via events."
      end

      # Check for eligible pending subtasks that can be assigned
      eligible_subtasks = find_eligible_pending_subtasks
      if eligible_subtasks.any?
        # Assign the highest priority eligible subtask
        next_subtask = select_next_subtask_to_assign(eligible_subtasks)
        agent_type = next_subtask.metadata&.dig("suggested_agent") || determine_best_agent_for_subtask(next_subtask)
        assign_result = assign_subtask(next_subtask.id, agent_type, "Assigning next eligible subtask during progress check")

        return "#{status_report}\\n\\n#{assign_result}"
      end

      # Default: just report status if no immediate action needed
      active_count = task.subtasks.where(state: "active").count
      pending_count = task.subtasks.where(state: "pending").count
      "#{status_report}\\n\\nTask is progressing with #{active_count} active subtasks and #{pending_count} pending (waiting on dependencies). No new subtasks are eligible for assignment yet."
    end
  end
end
