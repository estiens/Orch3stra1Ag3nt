module Agents
  class TestAgent < BaseAgent
    # Define queue name
    def self.queue_name
      :test_agent
    end

    # Tool for echoing LLM responses
    tool :llm_echo, "Returns an LLM completion for the input string" do |input|
      # Use the LLM to generate a response
      response = @llm.chat(messages: [{ role: "user", content: input }])
      
      # Record the LLM call
      record_llm_call(
        "openrouter",
        response.model || "unknown",
        input,
        response.chat_completion,
        response.total_tokens || 0
      )
      
      # Return the completion
      response.chat_completion
    end

    # Direct method for testing
    def llm_echo(input)
      execute_tool(:llm_echo, input)
    end

    # Override execute_chain to handle the input
    def execute_chain(input)
      if input.start_with?("llm_echo:")
        # Extract the query part
        query = input.sub("llm_echo:", "").strip
        # Call the llm_echo tool
        execute_tool(:llm_echo, query)
      else
        # Just pass to the LLM directly
        execute_tool(:llm_echo, input)
      end
    end
  end
end
