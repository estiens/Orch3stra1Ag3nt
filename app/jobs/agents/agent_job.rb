# Base AgentJob: Bridges Regent Agent to Solid Queue/Rails

class Agents::AgentJob < ApplicationJob
  # Queue as agents by default, but allow override
  queue_as :agents

  # Arguments: agent_class (BaseAgent subclass), run_args (for agent), options (hash)
  # Example: perform(OrchestratorAgent, { task_id: 123 }, { model: :thinking })
  # agent_prompt should be a String or an array of hashes, as per agent.run.
  def perform(agent_class, agent_prompt = nil, options = {})
    # Extract task_id from options
    task_id = options[:task_id]
    raise ArgumentError, "task_id is required" unless task_id.present?

    task = Task.find(task_id)
    task.activate! if task.pending?

    # Accept agent_class as String or constant
    agent_klass = agent_class.is_a?(String) ? agent_class.constantize : agent_class

    # Validate agent class is a BaseAgent subclass
    unless agent_klass <= BaseAgent
      raise ArgumentError, "agent_class must inherit from BaseAgent"
    end

    # NOTE: To use per-agent queueing, enqueue with set(queue: agent_class.queue_name)

    # Create AgentActivity record for tracking
    agent_activity = task.agent_activities.create!(
      agent_type: agent_klass.name,
      status: "active",
      metadata: options,
      parent_id: options[:parent_activity_id]
    )

    begin
      # Add thread isolation for agents if enabled
      maybe_with_ractor(agent_klass) do
        # Instantiate agent with a purpose (all model logic is handled by the agent itself)
        agent = agent_klass.new(
          options[:purpose] || "Agent run in async job",
          model: options[:model],
          task: task,
          agent_activity: agent_activity
        )

        prompt = agent_prompt || "Say hello!"

        # Log the start of agent execution
        Rails.logger.info("Starting agent job for #{agent_klass.name}, task_id: #{task_id}")

        # The before_run hook will be called by the agent
        # Run the agent
        result = agent.run(prompt)
        # The after_run hook will be called by the agent

        # Update agent activity with results
        agent_activity.update!(
          status: "completed",
          result: result,
          completed_at: Time.current
        )

        # Emit event for completed agent activity
        agent_activity.events.create!(
          event_type: "agent_completed",
          data: { result: result }
        )

        # If this is the last activity for the task, mark the task as completed
        if task.agent_activities.where.not(status: "completed").none?
          task.complete! if task.may_complete?
        end

        result
      end
    rescue => e
      # Use the error handler for standardized error processing
      error_context = {
        agent_class: agent_klass.name,
        agent_activity_id: agent_activity.id,
        task_id: task.id,
        prompt: agent_prompt&.respond_to?(:truncate) ? agent_prompt.truncate(100) : agent_prompt.to_s[0...100]
      }

      ErrorHandler.handle_error(e, error_context)

      # Update agent activity with error
      agent_activity.update!(
        status: "failed",
        error_message: e.message,
        completed_at: Time.current
      )

      # Create error event with more detailed information
      agent_activity.events.create!(
        event_type: "agent_failed",
        data: {
          error: e.message,
          error_class: e.class.name,
          recoverable: ErrorHandler::TRANSIENT_ERRORS.any? { |err| e.is_a?(err) }
        }
      )

      # Emit a system-wide error event for possible automatic recovery
      Event.publish(
        "agent_error",
        {
          agent_class: agent_klass.name,
          task_id: task.id,
          agent_activity_id: agent_activity.id,
          error: e.message,
          error_class: e.class.name
        },
        priority: Event::HIGH_PRIORITY
      )

      # Mark task as failed unless it's already in another terminal state
      task.fail! if task.may_fail?

      # Re-raise for Solid Queue's retry mechanism with improved context
      raise e, "#{e.message} (in #{agent_klass.name} job for task #{task.id})", e.backtrace
    end
  end

  private

  # Only use Ractor if Ruby version is 3.0+ and the ENABLE_RACTORS env var is set
  def maybe_with_ractor(agent_klass)
    if defined?(Ractor) && ENV["ENABLE_RACTORS"] == "true"
      # Attempt Ractor isolation if supported by Ruby version
      Rails.logger.info("Running #{agent_klass.name} in Ractor isolation")
      r = Ractor.new do
        Ractor.yield(yield)
      end
      r.take
    else
      # Fall back to regular execution (no isolation)
      yield
    end
  rescue => e
    Rails.logger.error("Ractor error: #{e.message}")
    # Fall back to regular execution
    yield
  end
end
