# frozen_string_literal: true

module ResearchCoordinator
  module Tools
    module KnowledgeManagement
      def consolidate_findings
        unless task
          return "Error: Cannot consolidate findings - Coordinator not associated with a main task."
        end

        task.reload
        completed_subtasks = task.subtasks.where(state: "completed")

        if completed_subtasks.empty?
          return "No completed research subtasks found for consolidation for task #{task.id}."
        end

        findings = completed_subtasks.map do |st|
          "Subtask: #{st.title}\nFindings:\n#{st.result || '(No result recorded)'}"
        end.join("\n\n---\n\n")

        prompt_content = consolidate_findings_prompt(task.title, findings)

        begin
          # Use the agent's LLM
          response = @llm.chat(messages: [ { role: "user", content: prompt_content } ])

          # Manually log the LLM call
          log_direct_llm_call(prompt_content, response)

          consolidated_result = response.chat_completion

          # Store result in the parent task
          task.update!(result: consolidated_result)

          # Event logging handled by callbacks

          # Publish system event (optional)

          consolidated_result
        rescue => e
          Rails.logger.error "[ResearchCoordinatorAgent] LLM Error in consolidate_findings: #{e.message}"
          "Error consolidating findings: #{e.message}"
        end
      end

      def check_existing_knowledge(query)
        # Placeholder for vector DB integration
        Rails.logger.info "[ResearchCoordinatorAgent] Tool check_existing_knowledge called (Not Implemented Yet). Query: #{query}"
        "Vector DB search not implemented yet. Cannot check existing knowledge."
      end

      def store_research_finding(finding, metadata = {})
        # Placeholder for vector DB integration
        Rails.logger.info "[ResearchCoordinatorAgent] Tool store_research_finding called (Not Implemented Yet). Finding: #{finding.truncate(50)}"
        "Vector DB storage not implemented yet. Cannot store finding."
      end

      def request_human_guidance(question, context = nil)
        unless task
          return "Error: Cannot request guidance - Coordinator not associated with a main task."
        end

        begin
          interaction = HumanInteraction.create!(
            interaction_type: "input_request", # Specify type
            task: task,
            question: question,
            required: true, # Guidance is usually required
            status: "pending",
            agent_activity: agent_activity,
            context: { context: context } # Use context instead of metadata? Check model.
            # Assuming metadata was mapped to context. If not, adjust.
          )

          task.wait_on_human! if task.may_wait_on_human?

          # Event log handled by callback

          # Publish system event
          EventService.publish(
            "research_guidance_requested",
            { # Data payload
              # request_id moved to metadata
              # task_id moved to metadata
              question: question,
              context: context
            },
            { # Metadata
              request_id: interaction.id, # Use interaction.id
              task_id: task.id
            }
            # Legacy priority option removed
          )

          "Research task #{task.id} is now waiting for human guidance on: '#{question}' (Request ID: #{interaction.id})" # Use interaction.id
        rescue => e
          Rails.logger.error "[ResearchCoordinatorAgent] Error requesting human guidance: #{e.message}"
          "Error requesting human guidance: #{e.message}"
        end
      end
    end
  end
end
