# Minimal Regent Agent for OpenRouter LLM integration test

class Agents::TestAgent < BaseAgent
  tool :llm_echo, "Returns an OpenRouter LLM completion for the input string" do |input|
    # In Regent, tools are invoked by the agent's reasoning process.
    # No need to call model.invoke directly; just return/manipulate input.
    "Echo: #{input}"
  end

  def after_run(result)
    Rails.logger.info("TestAgent session trace: #{@session_data.inspect}")
    super(result)
  end
end
