# Minimal Regent Agent for OpenRouter LLM integration test

class Agents::TestAgent < BaseAgent
  tool :llm_echo, "Returns an OpenRouter LLM completion for the input string"

  def llm_echo(input)
    # In Regent, tools are invoked by the agent's reasoning process.
    # No need to call model.invoke directly; just return/manipulate input.
    "Echo: #{input}"
  end

  def after_run
    Rails.logger.info("TestAgent session trace: \#{session_trace.inspect}")
  end
end
