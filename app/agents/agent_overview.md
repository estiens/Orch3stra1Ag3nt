# Agent Implementation Pattern (using langchainrb)

## Overview

This document outlines the implementation pattern for AI agents in this application, leveraging parts of the `langchainrb` gem (v0.19.4 or similar) and custom base classes. Each agent inherits from `BaseAgent`, which provides a structure for initialization, tool definition, manual logging, and background job integration (Solid Queue).

**Key Difference from Python LangChain:** As of this writing, `langchainrb` does **not** have built-in concepts of composable `Chain` classes (like `LLMChain`, `ToolChain`) or an automatic callback system. Therefore, agent orchestration logic (the sequence of LLM calls and tool usage) must be implemented imperatively within each agent subclass, typically by overriding the `run` method.

## BaseAgent Functionality

`app/agents/base_agent.rb` provides:

-   **Initialization (`initialize`)**: Sets up `@purpose`, `@task`, `@agent_activity`, `@llm`, and registered `@tools`.
-   **Tool Definition DSL**: `.tool` (for block-based tools) and `.custom_tool_objects` (for tool classes).
-   **Tool Execution Helper (`execute_tool`)**: A method to run defined tools, which *also* handles logging tool start/finish/error events to the associated `AgentActivity` (if present).
-   **LLM Instance (`@llm`)**: Provides a configured `langchainrb` LLM instance (e.g., `Langchain::LLM::OpenRouter`).
-   **Lifecycle Hooks**: `before_run`, `after_run`, `handle_run_error` for standard agent start/finish/error handling and updating `AgentActivity` status.
-   **Manual Logging Helpers**: `log_direct_llm_call` (for logging LLM calls made directly within agent code) and `persist_tool_executions` (called by hooks).
-   **SolidQueue Integration**: `.enqueue` method for background job processing.

## Agent Structure

### Basic Pattern

All specific agents should inherit from `BaseAgent` and implement their core logic by overriding the `run` method.

```ruby
# app/agents/my_orchestrating_agent.rb
class MyOrchestratingAgent < BaseAgent
  # === Configuration ===
  def self.queue_name
    :my_orchestrating_agent
  end

  def self.concurrency_limit
    1 # Example
  end

  # === Tool Definitions ===
  tool :step_one, "Performs the first step" do |input|
    # ... logic for step one ...
    "Step one result for #{input}"
  end

  tool :step_two, "Uses step one result" do |step_one_result|
    # ... logic for step two ...
    "Step two result based on: #{step_one_result}"
  end

  # === Core Logic ===
  # Override the run method to define the agent's workflow
  def run(input = nil)
    before_run(input) # Start lifecycle hook

    result_message = "Orchestration complete."
    begin
      # 1. Call the first tool using the helper for logging
      step_one_output = execute_tool(:step_one, input || @purpose)

      # 2. Make a direct LLM call (if needed) based on the result
      prompt = "Based on step one output '#{step_one_output}', what should be done next?"
      llm_response = @llm.chat(messages: [{ role: "user", content: prompt }])
      log_direct_llm_call(prompt, llm_response) # Log this manual call
      next_step_guidance = llm_response.chat_completion

      # 3. Call the second tool
      # (Assuming guidance indicates calling step_two with step_one_output)
      step_two_output = execute_tool(:step_two, step_one_output)

      result_message = step_two_output # Set final result

    rescue => e
      handle_run_error(e) # Handle errors
      raise # Re-raise after logging
    end

    @session_data[:output] = result_message # Store final output
    after_run(result_message) # Final lifecycle hook
    result_message
  end

  # Optional: Override other hooks like after_run for specific cleanup
end
```

## LLM Usage

-   **Configuration**: Handled by `BaseAgent.default_llm` or `llm:` option in `initialize`.
-   **Access**: Use `@llm` instance variable.
-   **Interaction**: Call `@llm.chat(...)` or `@llm.complete(...)` directly within your `run` method or tool implementations.
-   **Logging**: If you make direct calls to `@llm`, you **must manually log** them using the `log_direct_llm_call(prompt, response)` helper method (provided by `BaseAgent`) if you want them tracked in the `AgentActivity`'s `llm_calls` association.

## Tool Implementation & Usage

### Tool Definition

Define tools using either:

1.  **Block-Based (`self.tool`)**: Defined in the agent class. The block contains the tool's logic.
    ```ruby
    tool :my_block_tool, "Description" do |arg1|
      # self is the agent instance here
      internal_helper_method(arg1)
    end
    ```
2.  **Custom Tool Objects (`self.custom_tool_objects`)**: Separate classes, often extending `Langchain::ToolDefinition` (as seen in `PerplexitySearchTool.rb`). These are registered by returning instances from the class method `self.custom_tool_objects`.
    ```ruby
    # In MyAgent class
    def self.custom_tool_objects
      [ PerplexitySearchTool.new, AnotherCustomTool.new ]
    end
    ```

### Tool Execution & Logging

-   **Execution**: Within your agent's `run` method (or other helper methods), call tools using the `execute_tool(tool_name, *args)` helper provided by `BaseAgent`.
    ```ruby
    # Inside agent's run method
    result = execute_tool(:my_block_tool, "some argument")
    # For custom tools with defined functions:
    # execute_tool expects the method name defined by define_function
    perplexity_result = execute_tool(:search, { query: "AI agents in Ruby" })
    ```
-   **Logging**: The `execute_tool` method automatically handles logging `tool_execution_started`, `tool_execution_finished`, and `tool_execution_error` events to the `AgentActivity` (if present). You **do not** need to manually log tool calls made via `execute_tool`.
-   **Custom Tool Logging**: If a custom tool object makes its *own* internal LLM calls, it would need access to the `agent_activity` (perhaps passed during initialization) and would need to call `log_direct_llm_call` itself.

## Activity Logging & Tracing

Logging relies on the presence of an `AgentActivity` record.

-   **Association**: Pass an `AgentActivity` instance during agent initialization (`agent_activity:` parameter).
-   **Logging Summary**:
    -   **LLM Calls**: Logged **only** when `log_direct_llm_call` is called manually after a direct `@llm.chat`/`@llm.complete` call within agent code.
    -   **Tool Calls**: Logged **automatically** when tools are invoked via the `execute_tool` helper method. Records start/finish/error events.
    -   **Final Status**: `AgentActivity` status (`running`, `finished`, `failed`) and final `output` are updated automatically by `BaseAgent`'s lifecycle hooks (`before_run`, `after_run`, `handle_run_error`).
-   **Session Data (`@session_data`)**: Stores `:tool_executions` details captured by `execute_tool` during the run and the final `:output`.

## Job Integration (Solid Queue)

(This process remains the same)

1.  Create `AgentActivity` record.
2.  Enqueue job using `MyAgent.enqueue(prompt, { agent_activity_id: activity.id, ... })`.
3.  The `AgentJob` instantiates the agent, passing the `agent_activity` and other options, then calls `agent.run`.

## Best Practices

1.  **Override `run`**: All specific agents **must** override the `run` method to define their orchestration logic.
2.  **Use `execute_tool`**: Call tools via the `execute_tool` helper for automatic logging.
3.  **Log Direct LLM Calls**: Manually call `log_direct_llm_call` after direct `@llm` interactions if logging is needed.
4.  **Clear Purpose**: Design agents with single, clear responsibilities.
5.  **Error Handling**: Implement error handling within the `run` method and tool logic.
6.  **Configuration**: Use ENV vars or Rails config for external service keys/settings.

## Example Agent (Reflecting Final Pattern)

```ruby
# app/agents/simple_summarizer_agent.rb
class SimpleSummarizerAgent < BaseAgent

  def self.queue_name
    :simple_summarizer
  end

  # No tools defined for this simple example

  # Override run for specific summarization logic
  def run(input = nil)
    before_run(input)

    text_to_summarize = input || task&.description || @purpose || ""
    if text_to_summarize.blank?
      result = "Error: No text provided to summarize."
      @session_data[:output] = result
      after_run(result)
      return result
    end

    result_message = "Summarization failed."
    begin
      prompt = "Please summarize the following text concisely:\n\n#{text_to_summarize}"
      
      # Direct LLM call
      response = @llm.chat(messages: [{ role: "user", content: prompt }])
      
      # Manual logging
      log_direct_llm_call(prompt, response)
      
      result_message = response.chat_completion

    rescue => e
      handle_run_error(e)
      raise
    end

    @session_data[:output] = result_message
    after_run(result_message)
    result_message
  end
end

# --- Enqueuing --- 
# activity = AgentActivity.create!(agent_type: SimpleSummarizerAgent.name, ...)
# SimpleSummarizerAgent.enqueue(
#   "The text to be summarized...", 
#   { agent_activity_id: activity.id, purpose: "Summarize provided text" }
# )
```

## Advanced Patterns

(These concepts still apply, but are implemented within the agent's `run` method)

-   **Memory**: Fetch/update memory manually within the `run` method.
-   **Orchestration**: Implement multi-step logic, conditional tool calls, and agent spawning (using `.enqueue`) within the `run` method of coordinator agents.
-   **Event-driven Workflows**: Event handlers trigger agent jobs (`.enqueue`), which then execute their `run` method.
-   **RAG**: Implement retrieve-then-generate logic within the `run` method.