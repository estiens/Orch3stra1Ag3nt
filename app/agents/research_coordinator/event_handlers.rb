# frozen_string_literal: true

module ResearchCoordinator
  module EventHandlers
    # Handle new research task event - Typically triggered by Orchestrator
    def handle_new_research_task(event)
      task_id = event.data["task_id"]
      return if task_id.blank?

      # This handler might run in a separate instance context than the agent run.
      begin
        research_task = Task.find(task_id)
        Rails.logger.info "[ResearchCoordinatorAgentEventHandler] Received handle_new_research_task for Task #{task_id}: #{research_task.title}."
        # Option 1: Trigger a new agent run (most likely needed to start the process)
        # ResearchCoordinatorAgent.enqueue(
        #   "Plan research for: #{research_task.title}",
        #   { task_id: task_id, purpose: "Plan and execute research for task #{task_id}" }
        # )
      rescue ActiveRecord::RecordNotFound
        Rails.logger.error "[ResearchCoordinatorAgentEventHandler] Task #{task_id} not found for handle_new_research_task."
      end
    end

    # Handle research completion event
    def handle_research_completed(event)
      subtask_id = event.data["subtask_id"]
      return if subtask_id.blank?

      begin
        subtask = Task.find(subtask_id)
        parent_task = subtask.parent
        return unless parent_task # Ensure it's a subtask

        # Check if this event is relevant to an *active* coordinator for this parent task
        Rails.logger.info "[ResearchCoordinatorAgentEventHandler] Received handle_research_completed for Subtask #{subtask_id} (Parent: #{parent_task.id})."
        # An active coordinator for parent_task.id might trigger its run or call consolidate_findings tool.

      rescue ActiveRecord::RecordNotFound
         Rails.logger.error "[ResearchCoordinatorAgentEventHandler] Subtask #{subtask_id} not found for handle_research_completed."
      end
    end

    # Handle research failure event
    def handle_research_failed(event)
       subtask_id = event.data["subtask_id"]
       return if subtask_id.blank?

       begin
         subtask = Task.find(subtask_id)
         parent_task = subtask.parent
         return unless parent_task

         error = event.data["error"] || "Research failed with unknown error"
         Rails.logger.error "[ResearchCoordinatorAgentEventHandler] Received handle_research_failed for Subtask #{subtask_id} (Parent: #{parent_task.id}): #{error}"
         # An active coordinator for parent_task.id might trigger its run or try other actions.

       rescue ActiveRecord::RecordNotFound
          Rails.logger.error "[ResearchCoordinatorAgentEventHandler] Subtask #{subtask_id} not found for handle_research_failed."
       end
    end
  end
end
