# frozen_string_literal: true

module Coordinator
  module Tools
    module StatusManagement
      def update_task_status(status_message)
        unless task
          return "Error: Cannot update status - Coordinator not associated with a main task."
        end

        begin
          timestamp = Time.current.strftime("%Y-%m-%d %H:%M")
          # Append notes or replace? Let's append for now.
          new_notes = "#{task.notes}\n[#{timestamp} Coordinator Update]: #{status_message}".strip
          task.update!(notes: new_notes)

          agent_activity&.events.create!(
            event_type: "status_update",
            data: { task_id: task.id, message: status_message, timestamp: timestamp }
          )

          "✓ Task #{task.id} status updated: '#{status_message}'"
        rescue => e
          Rails.logger.error "[CoordinatorAgent] Error updating task status: #{e.message}"
          "Error updating task status: #{e.message}"
        end
      end

      def request_human_input(question, required = true)
        unless task
          return "Error: Cannot request human input - Coordinator not associated with a main task."
        end

        begin
          interaction = HumanInteraction.create!(
            interaction_type: "input_request", # Specify type
            task: task,
            question: question,
            required: required,
            status: "pending",
            agent_activity: agent_activity
            # context: {} # Add context if needed
          )

          if required && task.may_wait_on_human?
            task.wait_on_human!
            status_msg = "❗ Task #{task.id} is now BLOCKED waiting for required human input"
          else
            status_msg = "👤 Optional human input requested for task #{task.id} (will continue processing)"
          end

          EventService.publish(
            "human_input_requested",
            { # Data payload
              # request_id moved to metadata
              # task_id moved to metadata
              question: question,
              required: required
            },
            { # Metadata
              request_id: interaction.id, # Use interaction.id
              task_id: task.id,
              agent_activity_id: agent_activity&.id
              # Legacy priority option removed
            }
          )

          "#{status_msg}: '#{question}' (Request ID: #{interaction.id})" # Use interaction.id
        rescue => e
          Rails.logger.error "[CoordinatorAgent] Error requesting human input: #{e.message}"
          "Error requesting human input: #{e.message}"
        end
      end

      def mark_task_complete(summary = nil)
        unless task
          return "Error: Cannot mark complete - Coordinator not associated with a main task."
        end

        task.reload # Ensure we have the latest state
        incomplete_subtasks = task.subtasks.where.not(state: "completed")

        if incomplete_subtasks.any?
          subtask_details = incomplete_subtasks.map { |st| "#{st.id} (#{st.title}: #{st.state})" }.join(", ")
          return "⚠️ Cannot complete task #{task.id} - #{incomplete_subtasks.count} subtasks are incomplete: #{subtask_details}"
        end

        begin
          # Generate a comprehensive summary if none provided
          if summary.blank? && task.subtasks.any?
            summary = generate_completion_summary(task)
          end

          # Update with final summary
          task.update!(result: summary) if summary.present?

          if task.may_complete?
            task.complete!

            EventService.publish(
              "task_completed",
              { # Data payload
                # task_id moved to metadata
                result: summary
              },
              { # Metadata
                task_id: task.id,
                agent_activity_id: agent_activity&.id
              }
            )

            "✅ Task #{task.id} ('#{task.title}') successfully COMPLETED!"
          else
            "⚠️ Task #{task.id} cannot be completed from its current state: '#{task.state}'"
          end
        rescue => e
          Rails.logger.error "[CoordinatorAgent] Error marking task complete: #{e.message}"
          "Error marking task #{task.id} complete: #{e.message}"
        end
      end

      # Generate a comprehensive task summary from subtask results
      def generate_completion_summary(task)
        subtasks = task.subtasks.where(state: "completed")

        if subtasks.empty?
          return "Task completed without subtasks."
        end

        # Create a prompt for summarizing the results
        subtask_results = subtasks.map do |st|
          "## Subtask: #{st.title}\n#{st.result}"
        end.join("\n\n---\n\n")

        prompt = <<~PROMPT
          # TASK COMPLETION SUMMARY

          Generate a comprehensive, well-organized summary of this completed task based on the results of all subtasks.

          ## ORIGINAL TASK
          #{task.title}
          #{task.description}

          ## SUBTASK RESULTS
          #{subtask_results}

          ## REQUIRED OUTPUT FORMAT
          Create an executive summary that:
          1. Provides a high-level overview of what was accomplished
          2. Synthesizes the key findings/results from all subtasks
          3. Organizes information logically with clear section headings
          4. Highlights any important insights or recommendations
          5. Uses professional, concise language appropriate for a final report

          Your summary should be comprehensive but focused on the most relevant information.
        PROMPT

        begin
          response = @llm.chat(messages: [ { role: "user", content: prompt } ])
          log_direct_llm_call(prompt, response)
          response.chat_completion
        rescue => e
          Rails.logger.error "[CoordinatorAgent] Error generating completion summary: #{e.message}"
          "Task completed successfully. Error generating detailed summary: #{e.message}"
        end
      end
    end
  end
end
