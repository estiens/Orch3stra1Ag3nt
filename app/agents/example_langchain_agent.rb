class ExampleLangchainAgent < BaseAgent
  tool :search_web, "Search the web for information" do |query|
    # This is just a placeholder implementation
    "Results for: #{query}"
  end
  
  tool :calculate, "Perform a calculation" do |expression|
    eval(expression).to_s
  rescue => e
    "Error: #{e.message}"
  end
  
  def execute_chain(input)
    # Create a simple prompt template
    prompt = Langchain::Prompt::PromptTemplate.new(
      template: "You are a helpful assistant. Answer the following question: {question}",
      input_variables: ["question"]
    )
    
    # Create a simple LLM chain
    chain = Langchain::Chains::LLMChain.new(
      llm: @llm,
      prompt: prompt
    )
    
    # Run the chain
    result = chain.run(question: input)
    
    # Record the LLM call - assuming result is an OpenRouterResponse
    if result.respond_to?(:prompt_tokens)
      record_llm_call(
        "openrouter",
        @llm.defaults[:chat_model],
        input,
        result.to_s,
        result.prompt_tokens + result.completion_tokens
      )
    else
      record_llm_call(
        "openrouter",
        @llm.defaults[:chat_model],
        input,
        result.to_s,
        0
      )
    end
    
    # Return the result
    result
  end
end
