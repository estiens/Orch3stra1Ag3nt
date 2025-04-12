# Base AgentJob: Bridges Regent Agent to Solid Queue/Rails

class Agents::AgentJob < ApplicationJob
  # Arguments: agent_class (Regent::Agent subclass), run_args (for agent), options (hash)
  # Example: perform(OrchestratorAgent, { task_id: 123 }, { model: :thinking })
  # agent_prompt should be a String or an array of hashes, as per Regent agent.run.
  def perform(agent_class, agent_prompt = nil, options = {})
    # Accept agent_class as String or constant
    agent_klass = agent_class.is_a?(String) ? agent_class.constantize : agent_class
    unless agent_klass < Regent::Agent
      raise ArgumentError, "agent_class must inherit from Regent::Agent"
    end

    # NOTE: To use per-agent queueing, enqueue with set(queue: agent_class.queue_name)

    # Instantiate agent with a purpose (all model logic is handled by the agent itself)
    agent = agent_klass.new(
      "Agent run in async job"
    )

    prompt = agent_prompt || "Say hello!"
    agent.run(prompt)

      # Optionally: emit events or update domain models
      # Event.create!(kind: "agent_completed", agent: agent_class.name, args: {prompt: prompt})
    end
end
