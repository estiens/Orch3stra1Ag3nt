# frozen_string_literal: true

module Coordinator
  module Tools
    module TaskManagement
      def analyze_task(task_description)
        # Get project context if available
        project_context = ""
        if task&.project
          project = task.project
          project_context = <<~PROJECT
            ## PROJECT CONTEXT
            Project Name: #{project.name}
            Project Description: #{project.description}
            #{project.respond_to?(:goal) && project.goal.present? ? "Project Goal: #{project.goal}" : ""}
          PROJECT
        end

        prompt_content = <<~PROMPT
          # STRATEGIC TASK ANALYSIS

          As an expert project manager, analyze and decompose the following task into atomic, highly focused subtasks:

          #{project_context}
          ## TASK DESCRIPTION
          #{task_description}

          ## DECOMPOSITION STRATEGY
          1. Break this down into ATOMIC subtasks - each with a SINGLE clear focus and objective
          2. Prefer MORE GRANULAR subtasks over fewer complex ones
          3. For complex subtasks that require further decomposition, assign to CoordinatorAgent
          4. Arrange subtasks in logical execution order (dependencies first)
          5. Match specialized agent types to each subtask's specific requirements

          ## OUTPUT FORMAT
          For each subtask, provide:

          Subtask #{rand(1..100)}: {CLEAR, SPECIFIC TITLE}
          Description: {DETAILED instructions with success criteria}
          Priority: {high|normal|low}
          Agent: {ResearcherAgent|WebResearcherAgent|CodeResearcherAgent|WriterAgent|CoordinatorAgent|etc.}
          Dependencies: {List subtask numbers this depends on, or "None"}
          Complexity: {simple|moderate|complex} - Use "complex" to indicate subtasks that should be further decomposed

          ## SPECIALIZED AGENT TYPES
          - ResearcherAgent: General information gathering and analysis
          - WebResearcherAgent: Internet searches and web information retrieval
          - CodeResearcherAgent: Code analysis, generation, and explanation
          - WriterAgent: Content creation, editing, and formatting
          - AnalyzerAgent: Data analysis and insight generation
          - CoordinatorAgent: For complex subtasks that need further decomposition into smaller tasks

          ## IMPORTANT
          - Assign CoordinatorAgent to any subtask that could benefit from further decomposition
          - Ensure each subtask has a clear, measurable outcome
          - Create a comprehensive plan that when executed will FULLY accomplish the original task
        PROMPT

        begin
          response = @llm.chat(messages: [ { role: "user", content: prompt_content } ])
          log_direct_llm_call(prompt_content, response)
          response.chat_completion
        rescue => e
          Rails.logger.error "[CoordinatorAgent] Error during task analysis: #{e.message}"
          "Error analyzing task: #{e.message}"
        end
      end

      def create_subtask(title, description, priority = "normal")
        unless task
          return "Error: Cannot create subtask - Coordinator not associated with a main task."
        end

        begin
          # Validate priority
          normalized_priority = priority.to_s.downcase
          unless [ "high", "normal", "low" ].include?(normalized_priority)
            normalized_priority = "normal"
          end

          # Create a new agent activity for the subtask
          subtask_agent_activity = AgentActivity.create!(
            task: task,
            agent_type: "coordinator_agent",
            status: "pending",
            parent_id: agent_activity&.id,
            metadata: { purpose: "Subtask: #{title}" }
          )

          subtask = task.subtasks.create!(
            title: title,
            description: description,
            priority: normalized_priority,
            state: "pending", # Initial state
            metadata: { created_by: "coordinator_agent" }
          )

          # Create the required agent activity for the subtask
          subtask_agent_activity.update!(task: subtask)

          EventService.publish(
            "subtask.created", # Use dot notation for consistency
            { # Data payload
              # subtask_id moved to metadata
              # parent_id moved to metadata
              title: title,
              description: description, # Include description in event data
              priority: normalized_priority
            },
            { # Metadata
              subtask_id: subtask.id,
              parent_id: task.id,
              task_id: subtask.id, # Include task_id for consistency
              agent_activity_id: agent_activity&.id,
              project_id: task.project_id # Include project_id if available
            }
          )

          "Created subtask '#{title}' (ID: #{subtask.id}, Priority: #{normalized_priority}) for task #{task.id}"
        rescue => e
          Rails.logger.error "[CoordinatorAgent] Error creating subtask: #{e.message}"
          "Error creating subtask '#{title}': #{e.message}"
        end
      end

      def assign_subtask(subtask_id, agent_type, purpose = nil)
        unless task
          return "Error: Cannot assign subtask - Coordinator not associated with a main task."
        end

        begin
          subtask = task.subtasks.find(subtask_id)
        rescue ActiveRecord::RecordNotFound
          return "Error: Subtask with ID #{subtask_id} not found or does not belong to task #{task.id}."
        end

        # Check if the project is paused
        if task.project && task.project.status == "paused"
          return "Cannot assign subtask #{subtask_id} - Project #{task.project.id} (#{task.project.name}) is currently paused."
        end

        agent_class_name = agent_type.end_with?("Agent") ? agent_type : "#{agent_type.camelize}Agent"

        begin
          agent_class = agent_class_name.constantize
          unless agent_class < BaseAgent
            return "Error: #{agent_class_name} is not a valid BaseAgent subclass."
          end

          meaningful_purpose = purpose.presence || "Execute subtask: #{subtask.title}"

          agent_options = {
            task_id: subtask.id,
            parent_activity_id: agent_activity&.id,
            purpose: meaningful_purpose,
            task_priority: subtask.priority,
            metadata: {
              coordinator_id: agent_activity&.id,
              parent_task_id: task.id
            }
          }

          # Only add project_id if it exists to match test expectations
          agent_options[:project_id] = subtask.project_id if subtask.project_id.present?

          # Use the agent class's enqueue method
          job = agent_class.enqueue(
            "#{subtask.title}\n\n#{subtask.description}",
            agent_options
          )

          if job
            # Activate the subtask - this is being tested
            subtask.activate!

            subtask.update(
              metadata: (subtask.metadata || {}).merge({
                assigned_agent: agent_class_name,
                assigned_at: Time.current
              })
            )

            agent_activity&.events.create!(
              event_type: "subtask_assigned",
              data: { subtask_id: subtask.id, agent_type: agent_class_name, purpose: meaningful_purpose }
            )

            "Assigned subtask #{subtask_id} ('#{subtask.title}') to #{agent_class_name} with purpose: '#{meaningful_purpose}'."
          else
            "Warning: Subtask #{subtask_id} could not be assigned to #{agent_class_name} due to concurrency limits. It remains in '#{subtask.state}' state."
          end
        rescue NameError => e
          "Error: Agent type '#{agent_class_name}' not found. Available types: ResearcherAgent, WebResearcherAgent, CodeResearcherAgent, WriterAgent, AnalyzerAgent."
        rescue => e
          Rails.logger.error "[CoordinatorAgent] Error assigning subtask #{subtask_id}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
          "Error assigning subtask #{subtask_id}: #{e.message}"
        end
      end

      # Create a sub-coordinator agent to handle a complex subtask that needs further decomposition
      def create_sub_coordinator(subtask_id, purpose = nil)
        unless task
          return "Error: Cannot create sub-coordinator - Coordinator not associated with a main task."
        end

        begin
          subtask = task.subtasks.find(subtask_id)
        rescue ActiveRecord::RecordNotFound
          return "Error: Subtask with ID #{subtask_id} not found or does not belong to task #{task.id}."
        end

        # Check if the project is paused
        if task.project && task.project.status == "paused"
          return "Cannot create sub-coordinator for subtask #{subtask_id} - Project #{task.project.id} (#{task.project.name}) is currently paused."
        end

        # Create a meaningful purpose for the sub-coordinator
        meaningful_purpose = purpose.presence || "Sub-coordinator for complex subtask: #{subtask.title}"

        # Get complexity from metadata if available
        complexity = subtask.metadata&.dig("complexity") || "complex"

        # Prepare options for the sub-coordinator
        coordinator_options = {
          task_id: subtask.id,
          parent_activity_id: agent_activity&.id,
          purpose: meaningful_purpose,
          task_priority: subtask.priority,
          metadata: {
            parent_coordinator_id: agent_activity&.id,
            parent_task_id: task.id,
            is_sub_coordinator: true,
            original_subtask_id: subtask_id,
            complexity: complexity,
            nesting_level: (task.metadata&.dig("nesting_level") || 0) + 1
          }
        }

        # Create more detailed instructions based on the subtask complexity
        instructions = <<~INSTRUCTIONS
          # COMPLEX SUBTASK DECOMPOSITION

          This is a complex subtask that requires further decomposition into smaller, more atomic subtasks.

          ## Subtask: #{subtask.title}

          #{subtask.description}

          ## Decomposition Instructions
          1. Break this subtask down into highly atomic, focused sub-subtasks
          2. Make each sub-subtask as specific and focused as possible
          3. Ensure each sub-subtask has clear success criteria
          4. Assign specialized agents to each sub-subtask based on requirements

          ## Important Notes
          - This is a level #{coordinator_options[:metadata][:nesting_level]} nested coordinator
          - Focus on creating ATOMIC units of work that can be completed independently
          - Complexity assessment: #{complexity}
        INSTRUCTIONS

        # Enqueue the sub-coordinator
        job = CoordinatorAgent.enqueue(instructions, coordinator_options)

        if job
          # Update subtask state
          subtask.activate! if subtask.may_activate?

          # Update subtask metadata
          subtask.update(
            metadata: (subtask.metadata || {}).merge({
              assigned_agent: "CoordinatorAgent",
              assigned_at: Time.current,
              requires_decomposition: true
            })
          )

          # Create event for tracking
          agent_activity&.events.create!(
            event_type: "sub_coordinator_created",
            data: {
              subtask_id: subtask.id,
              purpose: meaningful_purpose,
              parent_coordinator_id: agent_activity&.id
            }
          )

          # Publish event for the system
          EventService.publish(
            "sub_coordinator_created",
            { # Data payload
              # subtask_id moved to metadata
              # parent_task_id moved to metadata
              # parent_coordinator_id moved to metadata
            },
            { # Metadata
              subtask_id: subtask.id,
              parent_task_id: task.id,
              parent_coordinator_id: agent_activity&.id,
              task_id: subtask.id, # Include task_id for consistency
              agent_activity_id: agent_activity&.id
            }
          )

          "Created sub-coordinator for subtask #{subtask_id} ('#{subtask.title}'). This subtask will be further decomposed into smaller tasks."
        else
          "Warning: Could not create sub-coordinator for subtask #{subtask_id} due to concurrency limits. It remains in '#{subtask.state}' state."
        end
      rescue => e
        Rails.logger.error "[CoordinatorAgent] Error creating sub-coordinator for subtask #{subtask_id}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        "Error creating sub-coordinator for subtask #{subtask_id}: #{e.message}"
      end

      def check_subtasks
        unless task
          return "Error: Cannot check subtasks - Coordinator not associated with a main task."
        end

        task.reload
        subtasks = task.subtasks.order(:created_at)

        if subtasks.empty?
          return "No subtasks found for task #{task.id}: '#{task.title}'."
        end

        # Generate statistics
        total = subtasks.count
        by_state = subtasks.group_by(&:state)
        by_priority = subtasks.group_by(&:priority)

        # Create detailed report
        report = <<~REPORT
          # SUBTASK STATUS REPORT

          ## Task: #{task.title} (ID: #{task.id})

          ### Summary Statistics
          - Total Subtasks: #{total}
          - Completed: #{by_state['completed']&.count || 0} (#{((by_state['completed']&.count || 0) * 100.0 / total).round}%)
          - In Progress: #{by_state['active']&.count || 0}
          - Pending: #{by_state['pending']&.count || 0}
          - Failed: #{by_state['failed']&.count || 0}
          - Other States: #{subtasks.count - (by_state['completed']&.count || 0) - (by_state['active']&.count || 0) - (by_state['pending']&.count || 0) - (by_state['failed']&.count || 0)}

          ### By Priority
          - High: #{by_priority['high']&.count || 0}
          - Normal: #{by_priority['normal']&.count || 0}
          - Low: #{by_priority['low']&.count || 0}

          ### Detailed Status
        REPORT

        # Add detailed subtask information
        subtasks.each do |st|
          agent_type = st.metadata&.dig("assigned_agent") || "Not assigned"
          created_at = st.created_at&.strftime("%Y-%m-%d %H:%M")
          status_icon = case st.state
          when "completed" then "✅"
          when "active" then "🔄"
          when "pending" then "⏳"
          when "failed" then "❌"
          when "waiting_on_human" then "👤"
          else "❓"
          end

          report += "#{status_icon} [ID #{st.id}][#{st.priority.upcase}] #{st.title} (#{agent_type}, created #{created_at})\n"
        end

        # Add recommendations based on status
        report += "\n### Recommendations\n"

        if by_state["failed"]&.any?
          report += "- URGENT: #{by_state['failed'].count} subtasks have failed and need attention.\n"
        end

        if by_state["pending"]&.any?
          report += "- #{by_state['pending'].count} subtasks are pending assignment.\n"
        end

        if by_state["completed"]&.count == total
          report += "- All subtasks are complete! Use mark_task_complete to finalize the task.\n"
        else
          completion_percentage = ((by_state["completed"]&.count || 0) * 100.0 / total).round
          report += "- Overall progress: #{completion_percentage}% complete.\n"
        end

        report
      end
    end
  end
end
