# frozen_string_literal: true

module Coordinator
  module EventHandlers
    # Handle subtask completed event
    def handle_subtask_completed(event)
      subtask_id = event.data["subtask_id"]
      return if subtask_id.blank?

      subtask = Task.find_by(id: subtask_id)
      return unless subtask

      parent_task = subtask.parent
      return unless parent_task

      Rails.logger.info "[CoordinatorAgent] Subtask #{subtask_id} completed. Evaluating next steps."

      # Initiate a new coordinator run to evaluate progress and determine next actions
      self.class.enqueue(
        "Evaluate progress after subtask #{subtask_id} (#{subtask.title}) completed",
        {
          task_id: parent_task.id,
          context: {
            event_type: "subtask_completed",
            subtask_id: subtask_id,
            result: event.data["result"]
          }
        }
      )
    end

    # Handle subtask failed event with recovery options
    def handle_subtask_failed(event)
      subtask_id = event.data["subtask_id"]
      return if subtask_id.blank?

      subtask = Task.find_by(id: subtask_id)
      return unless subtask

      parent_task = subtask.parent
      return unless parent_task

      error = event.data["error"] || "Unknown error"
      Rails.logger.error "[CoordinatorAgent] Subtask #{subtask_id} failed: #{error}"

      # Initiate a new coordinator run specifically to handle the failure
      self.class.enqueue(
        "Handle failure of subtask #{subtask_id} (#{subtask.title}): #{error}",
        {
          task_id: parent_task.id,
          context: {
            event_type: "subtask_failed",
            subtask_id: subtask_id,
            error: error
          }
        }
      )
    end

    # Handle human input required
    def handle_human_input_required(event)
      task_id = event.data["task_id"]

      # Find the task directly
      task = Task.find_by(id: task_id)
      return unless task

      question = event.data["question"]
      Rails.logger.warn "[CoordinatorAgent] Human input required: #{question}"

      # Initiate a new coordinator run to assess alternatives while waiting for human input
      self.class.enqueue(
        "Assess alternatives while waiting for human input on task #{task_id}",
        {
          task_id: task_id,
          context: {
            event_type: "human_input_required",
            question: question
          }
        }
      )
    end

    # Handle tool execution finished event
    def handle_tool_execution(event)
      begin
        # Extract relevant data from the event
        tool_name = event.data["tool"]
        result_preview = event.data["result_preview"]
        agent_activity_id = event.agent_activity_id

        # Only process events for agent activities
        return unless agent_activity_id

        # Find the agent activity
        activity = AgentActivity.find_by(id: agent_activity_id)
        return unless activity && activity.task_id

        # Log the tool execution
        Rails.logger.info "[CoordinatorAgent] Tool execution completed: #{tool_name}"

        # Enqueue a job to process this event with the proper task_id
        self.class.enqueue(
          "Process event: tool_execution_finished",
          {
            task_id: activity.task_id,
            purpose: "Process tool_execution_finished event",
            event_id: event.id
          }
        )
      rescue => e
        # Safely handle any errors during event processing
        Rails.logger.error "[CoordinatorAgent] Error handling tool execution event: #{e.message}"
      end
    end

    # Handle agent completed event
    def handle_agent_completed(event)
      begin
        # Extract relevant data
        result = event.data["result"]
        agent_activity_id = event.agent_activity_id

        return unless agent_activity_id

        # Look up the completed activity
        agent_activity = AgentActivity.find_by(id: agent_activity_id)
        return unless agent_activity

        # Get the associated task
        completed_task = agent_activity.task
        return unless completed_task

        # Get the parent task (which this coordinator is handling)
        parent_task_id = completed_task.parent_id
        return unless parent_task_id

        # Find the coordinator's task that matches the parent task
        coordinator_task = Task.find_by(id: parent_task_id)
        return unless coordinator_task

        Rails.logger.info "[CoordinatorAgent] Subtask #{completed_task.id} completed via agent activity #{agent_activity_id}"

        # Process as a subtask completed event
        # Reuse the subtask_completed handler logic using the new EventService
        subtask_completed_event = EventService.publish(
          "subtask.completed",
          {
            subtask_id: completed_task.id,
            result: result || "Task completed successfully"
          },
          {
            agent_activity_id: agent_activity&.id,
            task_id: completed_task.id,
            project_id: completed_task.project_id
          }
        )

        # Instead of calling handle_subtask_completed directly, enqueue a new job with the proper task_id
        self.class.enqueue(
          "Process event: agent_completed",
          {
            task_id: coordinator_task.id,
            purpose: "Process agent_completed event",
            event_id: subtask_completed_event.id
          }
        )
      rescue => e
        Rails.logger.error "[CoordinatorAgent] Error handling agent_completed event: #{e.message}"
      end
    end

    # Handle human input provided event
    def handle_human_input_provided(event)
      begin
        # Extract data from the event
        request_id = event.data["request_id"]
        input_task_id = event.data["task_id"] || event.task_id
        response = event.data["response"]

        # Skip if no task ID
        return if input_task_id.blank?

        # Find the task directly
        task = Task.find_by(id: input_task_id)
        return unless task

        Rails.logger.info "[CoordinatorAgent] Human input provided for task #{task.id}: #{response&.truncate(100)}"

        # Check if the task is waiting on human input
        is_waiting = task.waiting_on_human?

        # Only activate the task if it's waiting on human input
        if is_waiting
          # The task should be in waiting_on_human state, so activate it to resume processing
          task.activate! if task.may_activate?

          # Create a temporary agent activity to update task status
          temp_activity = AgentActivity.create!(
            task: task,
            agent_type: "CoordinatorAgent",
            status: "completed",
            metadata: { purpose: "Update task status after human input" }
          )

          # Use the task model directly to update status
          task.update!(
            notes: "#{task.notes}\n[#{Time.current.strftime("%Y-%m-%d %H:%M")} Coordinator Update]: Resuming task after human input: #{response&.truncate(50)}".strip
          )

          # Start a new coordinator run to continue processing
          self.class.enqueue(
            "Resume after human input provided",
            {
              task_id: task.id,
              context: {
                event_type: "task_resumed",
                input_request_id: request_id,
                response: response
              }
            }
          )
        end
      rescue => e
        Rails.logger.error "[CoordinatorAgent] Error handling human input provided: #{e.message}"
      end
    end

    # Handle project created event
    def handle_project_created(event)
      project_id = event.data["project_id"]
      return if project_id.blank?

      # Create a CoordinatorEventService to handle this event
      service = CoordinatorEventService.new
      service.handle_project_created(event, self)
    end

    # Handle project activated event
    def handle_project_activated(event)
      project_id = event.data["project_id"]
      return if project_id.blank?

      # Create a CoordinatorEventService to handle this event
      service = CoordinatorEventService.new
      service.handle_project_activated(event, self)
    end

    # Handle project stalled event
    def handle_project_stalled(event)
      project_id = event.data["project_id"]
      return if project_id.blank?

      # Create a CoordinatorEventService to handle this event
      service = CoordinatorEventService.new
      service.handle_project_stalled(event, self)
    end

    # Handle project recoordination request event
    def handle_project_recoordination(event)
      project_id = event.data["project_id"]
      return if project_id.blank?

      # Create a CoordinatorEventService to handle this event
      service = CoordinatorEventService.new
      service.handle_project_recoordination(event, self)
    end

    # Handle project paused event
    def handle_project_paused(event)
      project_id = event.data["project_id"]
      return if project_id.blank?

      # Create a CoordinatorEventService to handle this event
      service = CoordinatorEventService.new
      service.handle_project_paused(event, self)
    end

    # Handle project resumed event
    def handle_project_resumed(event)
      project_id = event.data["project_id"]
      return if project_id.blank?

      # Create a CoordinatorEventService to handle this event
      service = CoordinatorEventService.new
      service.handle_project_resumed(event, self)
    end
  end
end
