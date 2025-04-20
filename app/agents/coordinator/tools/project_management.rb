# frozen_string_literal: true

module Coordinator
  module Tools
    module ProjectManagement
      # Re-coordinate a project by analyzing progress and determining next steps
      def recoordinate_project(project_id)
        begin
          # Find the project
          project = Project.find(project_id)

          # Get all tasks for this project
          all_tasks = project.tasks
          completed_tasks = all_tasks.where(state: "completed")
          active_tasks = all_tasks.where(state: "active")
          pending_tasks = all_tasks.where(state: "pending")
          failed_tasks = all_tasks.where(state: "failed")
          waiting_tasks = all_tasks.where(state: "waiting_on_human")

          # Get the root task(s)
          root_tasks = project.root_tasks

          # Collect results from completed tasks
          completed_results = completed_tasks.map do |t|
            {
              id: t.id,
              title: t.title,
              result: t.result.present? ? t.result.truncate(500) : "No detailed result available"
            }
          end

          # Collect information about failed tasks
          failed_info = failed_tasks.map do |t|
            {
              id: t.id,
              title: t.title,
              error: t.metadata&.dig("error_message") || "Unknown error"
            }
          end

          # Collect information about tasks waiting on human input
          waiting_info = waiting_tasks.map do |t|
            # Find pending input requests for the task using the new model
            input_requests = HumanInteraction.input_requests.where(task_id: t.id, status: "pending")
            {
              id: t.id,
              title: t.title,
              questions: input_requests.map(&:question)
            }
          end

          # Create a comprehensive project status report
          project_status = {
            project_name: project.name,
            project_description: project.description,
            total_tasks: all_tasks.count,
            completed_count: completed_tasks.count,
            active_count: active_tasks.count,
            pending_count: pending_tasks.count,
            failed_count: failed_tasks.count,
            waiting_count: waiting_tasks.count,
            completion_percentage: all_tasks.count > 0 ? ((completed_tasks.count.to_f / all_tasks.count) * 100).round : 0,
            root_tasks: root_tasks.map { |t| { id: t.id, title: t.title, state: t.state } }
          }

          # Use LLM to analyze the project status and recommend next steps
          prompt = <<~PROMPT
            # PROJECT RE-COORDINATION ANALYSIS

            As an expert project coordinator, analyze the current state of this project and recommend the most appropriate next steps.

            ## PROJECT STATUS
            #{JSON.pretty_generate(project_status)}

            ## COMPLETED TASKS RESULTS
            #{JSON.pretty_generate(completed_results)}

            ## FAILED TASKS
            #{JSON.pretty_generate(failed_info)}

            ## TASKS WAITING ON HUMAN INPUT
            #{JSON.pretty_generate(waiting_info)}

            ## ANALYSIS REQUIREMENTS
            1. Evaluate overall project progress and identify any bottlenecks
            2. Determine if the project is on track or needs intervention
            3. Recommend ONE of the following actions:
               - CONTINUE: Project is progressing well, continue with current coordinators
               - NEW_COORDINATOR: Create a new coordinator to handle specific aspects
               - HUMAN_ESCALATION: Escalate to human for intervention
               - REPLAN: Project needs replanning due to significant issues

            ## REQUIRED OUTPUT FORMAT
            PROJECT_STATUS: [Brief assessment of current status]

            BOTTLENECKS:
            - [List any identified bottlenecks]

            RECOMMENDED_ACTION: [ONE of: CONTINUE, NEW_COORDINATOR, HUMAN_ESCALATION, REPLAN]

            JUSTIFICATION:
            [Detailed explanation of your recommendation]

            SPECIFIC_NEXT_STEPS:
            - [List specific actions to take]
          PROMPT

          response = @llm.chat(messages: [ { role: "user", content: prompt } ])
          log_direct_llm_call(prompt, response)
          analysis = response.chat_completion

          # Parse the LLM response to determine the recommended action
          recommended_action = analysis.match(/RECOMMENDED_ACTION:\s*(CONTINUE|NEW_COORDINATOR|HUMAN_ESCALATION|REPLAN)/)&.[](1)

          # Take action based on the recommendation
          action_result = case recommended_action
          when "CONTINUE"
            "Project #{project.name} is progressing well. Continuing with current coordination approach."
          when "NEW_COORDINATOR"
            # Find a suitable task to assign a new coordinator to
            target_task = active_tasks.first || pending_tasks.first || root_tasks.first

            if target_task
              # Create a new coordinator for this task
              coordinator_options = {
                task_id: target_task.id,
                parent_activity_id: agent_activity&.id,
                purpose: "Re-coordination of task after project analysis",
                metadata: {
                  recoordination_initiated_by: agent_activity&.id,
                  project_id: project.id
                }
              }

              CoordinatorAgent.enqueue(
                "Re-coordinate task execution for: #{target_task.title}\n#{target_task.description}",
                coordinator_options
              )

              "Created new coordinator for task #{target_task.id} (#{target_task.title}) to improve project coordination."
            else
              "Recommended creating a new coordinator, but couldn't find a suitable task to assign it to."
            end
          when "HUMAN_ESCALATION"
            # Extract the justification for escalation
            justification = analysis.match(/JUSTIFICATION:\s*(.*?)(?=\n\n|\z)/m)&.[](1)&.strip || "Project requires human intervention based on analysis."

            # Create a human intervention request
            intervention = HumanInteraction.create!(
              interaction_type: "intervention", # Specify type
              description: "PROJECT ESCALATION: #{project.name}\n\n#{justification}",
              urgency: "high",
              status: "pending",
              agent_activity_id: agent_activity&.id # Keep existing logic
            )

            EventService.publish(
              "human_intervention_requested",
              { # Data payload
                # intervention_id moved to metadata
                description: "Project escalation: #{project.name}",
                urgency: "high"
                # project_id moved to metadata
              },
              { # Metadata
                intervention_id: intervention.id,
                project_id: project.id
                # Legacy priority option removed
              }
            )

            "Escalated project #{project.name} to human operators. Intervention ID: #{intervention.id}"
          when "REPLAN"
            # Create a human input request for replanning
            interaction = HumanInteraction.create!(
              interaction_type: "input_request", # Specify type
              task: task || root_tasks.first,
              question: "Project #{project.name} needs replanning. Analysis suggests:\n\n#{analysis}",
              required: true,
              status: "pending",
              agent_activity: agent_activity
              # context: { project_id: project.id } # Add context if relevant
            )

            EventService.publish(
              "human_input_requested", # Keeping original event name for now
              { # Data payload
                # request_id moved to metadata
                # task_id moved to metadata
                question: "Project needs replanning",
                required: true
                # project_id moved to metadata
              },
              { # Metadata
                request_id: interaction.id, # Use interaction.id
                task_id: task&.id || root_tasks.first&.id,
                project_id: project.id,
                agent_activity_id: agent_activity&.id
                # Legacy priority option removed
              }
            )

            "Project #{project.name} needs replanning. Human input requested (ID: #{interaction.id})." # Use interaction.id
          else
            # Default action if parsing fails
            "Analyzed project #{project.name} (#{completed_tasks.count}/#{all_tasks.count} tasks completed). Unable to determine specific action from analysis."
          end

          # Return the full analysis and the action taken
          "#{analysis}\n\nACTION TAKEN: #{action_result}"

        rescue ActiveRecord::RecordNotFound
          "Error: Project with ID #{project_id} not found."
        rescue => e
          Rails.logger.error "[CoordinatorAgent] Error in recoordinate_project: #{e.message}"
          "Error re-coordinating project #{project_id}: #{e.message}"
        end
      end
    end
  end
end
