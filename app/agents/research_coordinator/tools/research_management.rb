# frozen_string_literal: true

module ResearchCoordinator
  module Tools
    module ResearchManagement
      def analyze_research_question(research_question)
        prompt_content = analyze_research_question_prompt(research_question)

        begin
          # Use the agent's LLM instance provided by BaseAgent
          response = @llm.chat(messages: [ { role: "user", content: prompt_content } ])

          # Manually log the LLM call
          log_direct_llm_call(prompt_content, response)

          response.chat_completion
        rescue => e
          Rails.logger.error "[ResearchCoordinatorAgent] LLM Error in analyze_research_question: #{e.message}"
          "Error analyzing research question: #{e.message}"
        end
      end

      def create_research_subtask(title, description, methods = nil)
        unless task
          return "Error: Cannot create research subtask - Coordinator not associated with a main task."
        end

        begin
          metadata = {}
          metadata[:research_methods] = Array(methods) if methods.present?

          subtask = task.subtasks.create!(
            title: title,
            description: description,
            priority: "normal",
            state: "pending",
            metadata: metadata
          )

          # Event logging within the agent activity is handled by callbacks if this is called via a tool
          # If called directly, manual logging might be needed, but tools are preferred.

          # Publish system-wide event
          EventService.publish(
            "research_subtask_created",
            { # Data payload
              # subtask_id moved to metadata
              # parent_id moved to metadata
              title: title,
              methods: methods
            },
            { # Metadata
              subtask_id: subtask.id,
              parent_id: task.id,
              task_id: subtask.id # Also include task_id for consistency if needed
            }
          )

          "Created research subtask '#{title}' (ID: #{subtask.id}) for task #{task.id}"
        rescue => e
          Rails.logger.error "[ResearchCoordinatorAgent] Error creating research subtask: #{e.message}"
          "Error creating research subtask '#{title}': #{e.message}"
        end
      end

      def assign_researcher(subtask_id, methods = [])
        unless task
          return "Error: Cannot assign researcher - Coordinator not associated with a main task."
        end

        begin
          subtask = task.subtasks.find(subtask_id)
        rescue ActiveRecord::RecordNotFound
          return "Error: Subtask #{subtask_id} not found or does not belong to task #{task.id}."
        end

        researcher_type = determine_researcher_type(methods)

        begin
          agent_class = researcher_type.constantize
          unless agent_class < BaseAgent
            return "Error: #{researcher_type} is not a valid BaseAgent subclass."
          end

          agent_options = {
            task_id: subtask.id,
            parent_activity_id: agent_activity&.id,
            purpose: "Research: #{subtask.title}"
          }

          agent_class.enqueue(
            "Conduct research on: #{subtask.title}\n\n#{subtask.description}\n\nUse methods: #{Array(methods).join(', ')}",
            agent_options
          )

          subtask.activate! if subtask.may_activate?

          # Event logging within activity handled by callbacks if called via tool

          # Publish system-wide event (optional, maybe redundant with callback log)

          "Assigned research subtask #{subtask_id} ('#{subtask.title}') to #{researcher_type}."
        rescue NameError
          "Error: Researcher type '#{researcher_type}' not found."
        rescue => e
          Rails.logger.error "[ResearchCoordinatorAgent] Error assigning researcher for subtask #{subtask_id}: #{e.message}"
          "Error assigning researcher: #{e.message}"
        end
      end
    end
  end
end
