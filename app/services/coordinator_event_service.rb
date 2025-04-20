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

      # Publish event for dashboard notification using EventService
      EventService.publish(
        "human_input.requested",
        {
          request_id: input_request.id,
          prompt: prompt,
          request_type: options[:type] || "text",
          task_id: task.id
        },
        {
          task_id: task.id,
          project_id: task.project_id
        }
      )

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
      # Find the interaction (input request type)
      interaction = HumanInteraction.find_by(id: request_id, interaction_type: "input_request")

      if interaction.nil?
        logger.error("HumanInteraction (Input Request) not found with ID: #{request_id}")
        return nil
      end

      # Publish an event indicating that human input has been processed
      # A separate handler will update the interaction and task status
      user_id = event.metadata["user_id"] # Assuming user_id might be in metadata

      EventService.publish(
        "human_input.processed",
        {
          request_id: request_id,
          input: input,
          task_id: interaction.task_id, # Get task_id from interaction
          user_id: user_id # Include user_id if available
        },
        event.metadata # Pass along original metadata
      )

      # Find the associated task
      task = interaction.task # Use the interaction to find the task

      if task.nil?
        # Use interaction.id for logging consistency
        logger.error("Task not found for HumanInteraction (Input Request): #{interaction.id}")
        return nil
      end

      # Resume the task with the provided input
      # Note: The resume logic is now handled within interaction.answer! if needed.
      # We might still need to process the input further depending on application logic.
      if task.state == "waiting_on_human"
        logger.info("Task #{task.id} was potentially resumed by HumanInteraction #{interaction.id}. Processing input.")
        # task.resume! # This is now handled internally by answer! -> resume_task
        # Process the human input for the task, using the interaction object
        process_human_input(task, input, interaction)
      else
        # If the task wasn't waiting, maybe just log the input processing?
        logger.warn("Task #{task.id} not in waiting_on_human state, but received input for HumanInteraction #{interaction.id}. Processing input.")
        process_human_input(task, input, interaction) # Still process the input? Depends on logic.
      end

      { task: task, interaction: interaction } # Return the interaction object
    end
  end

  # Handle a new project event
  # @param event [Event] the project_created event
  # @param agent [CoordinatorAgent] the agent instance
  # @return [Object] the result of processing
  def handle_project_created(event, agent)
    process_event(event, "CoordinatorEventService#handle_project_created") do
      validate_event_data(event, [ "project_id" ])

      project_id = event.data["project_id"]
      project = Project.find_by(id: project_id)

      if project.nil?
        logger.error("Project not found with ID: #{project_id}")
        return nil
      end

      logger.info("Project created: #{project.name} [#{project.id}]")

      # The project should already have a coordinator task created
      # in the Project#kickoff! method, so we just ensure it's active
      root_task = project.root_tasks.where(task_type: "coordination").first

      if root_task && root_task.may_activate?
        root_task.activate!
        logger.info("Root coordination task activated: #{root_task.id}")
      end

      { project: project, root_task: root_task }
    end
  end

  # Handle project activation event
  # @param event [Event] the project_activated event
  # @param agent [CoordinatorAgent] the agent instance
  # @return [Object] the result of processing
  def handle_project_activated(event, agent)
    process_event(event, "CoordinatorEventService#handle_project_activated") do
      validate_event_data(event, [ "project_id" ])

      project_id = event.data["project_id"]
      project = Project.find_by(id: project_id)

      if project.nil?
        logger.error("Project not found with ID: #{project_id}")
        return nil
      end

      logger.info("Project activated: #{project.name} [#{project.id}]")

      # Ensure coordination task is active, and decompose if needed
      root_task = project.root_tasks.where(task_type: "coordination").first

      if root_task && agent.task&.id == root_task.id
        logger.info("Initiating project decomposition for #{project.name}")
        # The agent handling this event should perform task decomposition
        # This will happen in its run method
      end

      { project: project, root_task: root_task }
    end
  end

  # Handle project stalled event
  # @param event [Event] the project_stalled event
  # @param agent [CoordinatorAgent] the agent instance
  # @return [Object] the result of processing
  def handle_project_stalled(event, agent)
    process_event(event, "CoordinatorEventService#handle_project_stalled") do
      validate_event_data(event, [ "project_id" ])

      project_id = event.data["project_id"]
      project = Project.find_by(id: project_id)

      if project.nil?
        logger.error("Project not found with ID: #{project_id}")
        return nil
      end

      logger.info("Project stalled: #{project.name} [#{project.id}]")

      # Check if this agent is responsible for this project
      if agent.task&.project_id == project.id
        logger.info("Coordinator will re-evaluate stalled project #{project.name}")
        # The coordinator should re-evaluate the project in its run method
      end

      { project: project }
    end
  end

  # Handle project recoordination request
  # @param event [Event] the project_recoordination_requested event
  # @param agent [CoordinatorAgent] the agent instance
  # @return [Object] the result of processing
  def handle_project_recoordination(event, agent)
    process_event(event, "CoordinatorEventService#handle_project_recoordination") do
      validate_event_data(event, [ "project_id" ])

      project_id = event.data["project_id"]
      project = Project.find_by(id: project_id)

      if project.nil?
        logger.error("Project not found with ID: #{project_id}")
        return nil
      end

      logger.info("Project recoordination requested: #{project.name} [#{project.id}]")

      # Check if this agent is responsible for the project's root task
      root_task = project.root_tasks.where(task_type: "coordination").first

      if root_task && agent.task&.id == root_task.id
        logger.info("Coordinator will recoordinate project #{project.name}")
        # The agent handling this event should perform recoordination
        # This will happen in its run method
      end

      { project: project, root_task: root_task }
    end
  end

  # Handle project paused event
  # @param event [Event] the project_paused event
  # @param agent [CoordinatorAgent] the agent instance
  # @return [Object] the result of processing
  def handle_project_paused(event, agent)
    process_event(event, "CoordinatorEventService#handle_project_paused") do
      validate_event_data(event, [ "project_id" ])

      project_id = event.data["project_id"]
      project = Project.find_by(id: project_id)

      if project.nil?
        logger.error("Project not found with ID: #{project_id}")
        return nil
      end

      logger.info("Project paused: #{project.name} [#{project.id}]")

      # If this agent is responsible for the project, it should pause its operations
      if agent.task&.project_id == project.id
        logger.info("Coordinator acknowledging project pause for #{project.name}")

        # If the agent's task is active, pause it
        if agent.task.state == "active" && agent.task.may_pause?
          agent.task.pause!
          logger.info("Paused coordination task: #{agent.task.id}")
        end
      end

      { project: project }
    end
  end

  # Handle project resumed event
  # @param event [Event] the project_resumed event
  # @param agent [CoordinatorAgent] the agent instance
  # @return [Object] the result of processing
  def handle_project_resumed(event, agent)
    process_event(event, "CoordinatorEventService#handle_project_resumed") do
      validate_event_data(event, [ "project_id" ])

      project_id = event.data["project_id"]
      project = Project.find_by(id: project_id)

      if project.nil?
        logger.error("Project not found with ID: #{project_id}")
        return nil
      end

      logger.info("Project resumed: #{project.name} [#{project.id}]")

      # If this agent is responsible for the project, it should resume its operations
      if agent.task&.project_id == project.id
        logger.info("Coordinator acknowledging project resume for #{project.name}")

        # If the agent's task is paused, resume it
        if agent.task.state == "paused" && agent.task.may_resume?
          agent.task.resume!
          logger.info("Resumed coordination task: #{agent.task.id}")
        end

        # Request recoordination to ensure progress continues using EventService
        EventService.publish(
          "project.recoordination_requested",
          {
            project_id: project.id,
            project_name: project.name,
            reason: "Project resumed after being paused"
          },
          {
            task_id: agent.task.id,
            project_id: project.id
          }
        )
      end

      { project: project }
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
