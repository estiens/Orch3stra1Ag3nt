# frozen_string_literal: true

# CoordinatorEventService handles event processing for the CoordinatorAgent
# This centralizes all the event handling logic for the coordinator
class CoordinatorEventService < BaseEventService
  # Handle a completed subtask event
  # @param event [Event] the subtask_completed event
  # @param agent [CoordinatorAgent] the agent instance
  # @return [Object] the result of processing
  def handle_subtask_completed(event, agent)
    process_event(event, "CoordinatorEventService#handle_subtask_completed") do
      validate_event_data(event, [ "subtask_id", "task_id", "result" ])

      subtask_id = event.data["subtask_id"]
      task_id = event.data["task_id"]
      result = event.data["result"]

      logger.info("Subtask completed: #{subtask_id} for task: #{task_id}")

      task = Task.find_by(id: task_id)

      if task.nil?
        logger.error("Task not found with ID: #{task_id}")
        return nil
      end

      # Update task with subtask result
      # This might involve storing the result, updating progress, etc.

      # Check if all subtasks are complete
      if task_complete?(task)
        logger.info("All subtasks complete for task: #{task.id}")
        task.complete!
      else
        logger.info("Task progress updated: #{task.id}")
      end

      { task: task, subtask_id: subtask_id, complete: task.completed? }
    end
  end

  # Handle a failed subtask event
  # @param event [Event] the subtask_failed event
  # @param agent [CoordinatorAgent] the agent instance
  # @return [Object] the result of processing
  def handle_subtask_failed(event, agent)
    process_event(event, "CoordinatorEventService#handle_subtask_failed") do
      validate_event_data(event, [ "subtask_id", "task_id", "error" ])

      subtask_id = event.data["subtask_id"]
      task_id = event.data["task_id"]
      error = event.data["error"]

      logger.error("Subtask failed: #{subtask_id} for task: #{task_id}, error: #{error}")

      task = Task.find_by(id: task_id)

      if task.nil?
        logger.error("Task not found with ID: #{task_id}")
        return nil
      end

      # Determine if the subtask failure is critical for the task
      if critical_subtask?(subtask_id, task)
        logger.error("Critical subtask failure, marking task as failed: #{task.id}")
        task.mark_failed(error)
      else
        logger.info("Non-critical subtask failure, attempting recovery: #{task.id}")
        # Implement recovery strategy
        recover_from_subtask_failure(subtask_id, task, error)
      end

      { task: task, subtask_id: subtask_id, critical_failure: critical_subtask?(subtask_id, task) }
    end
  end

  # Handle a task waiting on human input event
  # @param event [Event] the task_waiting_on_human event
  # @param agent [CoordinatorAgent] the agent instance
  # @return [Object] the result of processing
  def handle_human_input_required(event, agent)
    process_event(event, "CoordinatorEventService#handle_human_input_required") do
      validate_event_data(event, [ "task_id", "prompt" ])

      task_id = event.data["task_id"]
      prompt = event.data["prompt"]
      options = event.data["options"] || {}

      logger.info("Task waiting on human input: #{task_id}, prompt: #{prompt}")

      task = Task.find_by(id: task_id)

      if task.nil?
        logger.error("Task not found with ID: #{task_id}")
        return nil
      end

      # Create a human input request
      input_request = HumanInputRequest.create!(
        task: task,
        prompt: prompt,
        options: options,
        status: "pending"
      )

      # Update task status
      task.update(status: "waiting_on_human")

      # Publish event for dashboard notification
      task.publish_event("human_input.requested", {
        request_id: input_request.id,
        prompt: prompt,
        request_type: options[:type] || "text",
        task_id: task.id
      })

      { task: task, input_request: input_request }
    end
  end

  # Handle a tool execution finished event
  # @param event [Event] the tool_execution_finished event
  # @param agent [CoordinatorAgent] the agent instance
  # @return [Object] the result of processing
  def handle_tool_execution(event, agent)
    process_event(event, "CoordinatorEventService#handle_tool_execution") do
      validate_event_data(event, [ "tool_name", "result" ])

      tool_name = event.data["tool_name"]
      result = event.data["result"]
      task_id = event.data["task_id"]

      logger.info("Tool execution finished: #{tool_name} for task: #{task_id}")

      # If task_id is provided, update the task with the tool result
      if task_id.present?
        task = Task.find_by(id: task_id)

        if task.nil?
          logger.error("Task not found with ID: #{task_id}")
        else
          # Process tool result for the task
          process_tool_result(task, tool_name, result)
        end
      end

      { tool_name: tool_name, task_id: task_id }
    end
  end

  # Handle an agent completed event
  # @param event [Event] the agent_completed event
  # @param agent [CoordinatorAgent] the agent instance
  # @return [Object] the result of processing
  def handle_agent_completed(event, agent)
    process_event(event, "CoordinatorEventService#handle_agent_completed") do
      validate_event_data(event, [ "agent_id", "agent_type", "result" ])

      agent_id = event.data["agent_id"]
      agent_type = event.data["agent_type"]
      result = event.data["result"]
      task_id = event.data["task_id"]

      logger.info("Agent completed: #{agent_type} [#{agent_id}] for task: #{task_id}")

      # If task_id is provided, update the task with the agent result
      if task_id.present?
        task = Task.find_by(id: task_id)

        if task.nil?
          logger.error("Task not found with ID: #{task_id}")
        else
          # Process agent result for the task
          process_agent_result(task, agent_type, result)
        end
      end

      { agent_type: agent_type, agent_id: agent_id, task_id: task_id }
    end
  end

  # Handle a human input provided event
  # @param event [Event] the human_input_provided event
  # @param agent [CoordinatorAgent] the agent instance
  # @return [Object] the result of processing
  def handle_human_input_provided(event, agent)
    process_event(event, "CoordinatorEventService#handle_human_input_provided") do
      validate_event_data(event, [ "input", "request_id" ])

      input = event.data["input"]
      request_id = event.data["request_id"]

      logger.info("Human input provided for request: #{request_id}")

      # Find the input request
      input_request = HumanInputRequest.find_by(id: request_id)

      if input_request.nil?
        logger.error("Input request not found with ID: #{request_id}")
        return nil
      end

      # Update the input request
      input_request.update(
        response: input,
        status: "completed",
        responded_at: Time.current
      )

      # Find the associated task
      task = input_request.task

      if task.nil?
        logger.error("Task not found for input request: #{request_id}")
        return nil
      end

      # Resume the task with the provided input
      if task.status == "waiting_on_human"
        logger.info("Resuming task with human input: #{task.id}")
        task.resume!

        # Process the human input for the task
        process_human_input(task, input, input_request)
      else
        logger.warn("Task not in waiting_on_human status: #{task.id}, current status: #{task.status}")
      end

      { task: task, input_request: input_request }
    end
  end

  private

  # Check if all subtasks for a task are complete
  def task_complete?(task)
    # Implementation would depend on how subtasks are tracked
    # This is a placeholder
    true
  end

  # Check if a subtask is critical for a task
  def critical_subtask?(subtask_id, task)
    # Implementation would depend on how critical subtasks are defined
    # This is a placeholder
    false
  end

  # Recover from a subtask failure
  def recover_from_subtask_failure(subtask_id, task, error)
    logger.info("Attempting to recover from subtask failure: #{subtask_id} for task: #{task.id}")
    # Implementation details
  end

  # Process a tool execution result for a task
  def process_tool_result(task, tool_name, result)
    logger.info("Processing tool result for task: #{task.id}, tool: #{tool_name}")
    # Implementation details
  end

  # Process an agent result for a task
  def process_agent_result(task, agent_type, result)
    logger.info("Processing agent result for task: #{task.id}, agent: #{agent_type}")
    # Implementation details
  end

  # Process human input for a task
  def process_human_input(task, input, input_request)
    logger.info("Processing human input for task: #{task.id}")
    # Implementation details
  end
end
