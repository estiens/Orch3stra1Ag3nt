# Agent Implementation with LangchainRB

## Overview

This document outlines the implementation pattern for AI agents in our application using the `langchainrb` gem. Each agent inherits from `BaseAgent`, which provides a standard structure for initialization, tool definition, chain execution, and integration with our background job system (Solid Queue) and activity tracking (`AgentActivity` model).

## Agent Structure

### Basic Pattern

All agents should inherit from `BaseAgent` and generally follow this structure:

```ruby
# app/agents/my_special_agent.rb
require_relative '../callbacks/agent_activity_callback_handler' # Ensure callbacks are loaded

class MySpecialAgent < BaseAgent
  # Optional: Include EventSubscriber if needed
  # include EventSubscriber

  # === Configuration ===

  # Queue configuration for Solid Queue
  def self.queue_name
    :my_special_agent # Use a descriptive queue name
  end

  def self.concurrency_limit
    3 # Adjust based on agent resource needs and external API limits
  end

  # Optional: Define a default LLM for this agent class
  # def self.default_llm
  #   # Return a configured Langchain::LLM instance
  #   Langchain::LLM::OpenRouter.new(...)
  # end

  # Optional: Define default custom tool *objects* for this agent class
  # def self.custom_tool_objects
  #   [ MyCustomTool.new, AnotherTool.new(api_key: ENV['...']) ]
  # end

  # === Tool Definitions ===
  # Define tools using blocks (creates Langchain::Tool::Function)
  tool :my_block_tool, "Description of what this tool does" do |arg1, arg2|
    # Tool implementation logic here...
    # Access instance variables like @task or @agent_activity if needed
    result = perform_action(arg1, arg2)
    result # Return value is passed back to the agent chain
  end

  # You can define multiple tools

  # === Initialization ===
  # Inherits initialize from BaseAgent. Key parameters:
  # - purpose: (String) The goal of this specific agent instance.
  # - llm: (Langchain::LLM::Base, optional) Override default LLM.
  # - retriever: (Langchain::Retriever::Base, optional) Provide a retriever.
  # - tools: (Array<Langchain::Tool::Base>, optional) Override default tools.
  # - task: (Task, optional) Associated Task record.
  # - agent_activity: (AgentActivity, optional) Associated AgentActivity for logging.

  # === Chain Setup ===
  # BaseAgent's `setup_chain!` automatically configures a suitable chain
  # (LLMChain, ToolChain, RetrievalQAChain) based on whether tools or a
  # retriever are present. Override `setup_chain!` for custom chain logic.

  # === Core Logic ===
  # The main logic is executed by the `run` method inherited from BaseAgent,
  # which calls `@chain.run`. For simple agents, you often don't need to
  # override `run` or `setup_chain!`.

  # === Lifecycle Hooks ===
  # Optional overrides for custom setup/teardown:
  # def before_run(input)
  #   super # Call base implementation first
  #   # Custom logic before chain execution
  # end
  #
  # def after_run(result)
  #   super # Call base implementation first
  #   # Custom logic after chain execution
  # end
  #
  # def handle_run_error(e)
  #   super # Call base implementation first (logs error, marks activity failed)
  #   # Custom error handling
  # end

  private

  def perform_action(arg1, arg2)
    # Example private helper method used by a tool
    "Processed #{arg1} and #{arg2}"
  end
end
```

## LLM Usage

Agents use `langchainrb` LLM wrappers (e.g., `Langchain::LLM::OpenRouter`).

- **Configuration**: The default LLM is configured in `BaseAgent.default_llm` or can be overridden per-agent class. An instance can also receive a specific LLM during initialization (`llm:` parameter).
- **Access**: Within agent methods (like tools), access the configured LLM via the `@llm` instance variable.
- **Interaction**: Use standard `langchainrb` methods like `@llm.chat(...)` or let the configured chain handle the interaction.

```ruby
# Inside a tool block or other instance method:
prompt_content = "Translate 'hello' to French."
response = @llm.chat(messages: [{ role: "user", content: prompt_content }])
translation = response.chat_completion
```

## Tool Implementation

### Tool Definition

There are two primary ways to define tools for an agent:

1.  **Block-Based (`self.tool`)**: Define simple tools directly in the agent class using the `self.tool` DSL. This creates a `Langchain::Tool::Function` instance.

    ```ruby
    tool :calculate, "Perform mathematical calculations" do |expression|
      begin
        # Ensure safe evaluation if using eval
        result = SafeCalculator.evaluate(expression)
        result.to_s
      rescue => e
        "Calculation error: #{e.message}"
      end
    end
    ```

2.  **Custom Tool Objects (`self.custom_tool_objects`)**: For complex tools, tools requiring configuration (e.g., API keys), or tools shared across agents, define them as separate classes that implement the `Langchain::Tool::Base` interface (typically just a `call` method). Register instances of these classes by overriding `self.custom_tool_objects` in your agent:

    ```ruby
    # app/tools/my_api_tool.rb
    class MyApiTool < Langchain::Tool::Base
      def initialize(api_key:)
        @client = MyApiClient.new(api_key)
      end

      def call(input:)
        @client.fetch(input)
      end
    end

    # app/agents/my_special_agent.rb
    class MySpecialAgent < BaseAgent
      def self.custom_tool_objects
        [ MyApiTool.new(api_key: ENV['MY_API_KEY']) ]
      end
      # ... potentially other tools defined with self.tool ...
    end
    ```

### Tool Usage

- **Automatic Setup**: `BaseAgent` gathers all tools (from `self.tool` blocks and `self.custom_tool_objects`) and passes them to the appropriate `langchainrb` chain (e.g., `Langchain::Chains::ToolChain`) during `setup_chain!`.
- **Chain Execution**: The chain (e.g., `ToolChain`, `ReAct`) decides when and how to call the tools based on the LLM's reasoning. You typically do *not* call tool methods directly within your agent's main flow; the chain handles it.

## Activity Logging & Tracing

Detailed logging of agent activity is crucial for debugging and monitoring. This is handled **automatically** when an `AgentActivity` record is associated with the agent instance.

- **Association**: Pass an `AgentActivity` instance during agent initialization:
    ```ruby
    activity = AgentActivity.create!(...)
    agent = MySpecialAgent.new(purpose: "...", agent_activity: activity)
    agent.run("some input")
    ```
- **Callback Handler**: `BaseAgent` initializes an `AgentActivityCallbackHandler` which subscribes to `langchainrb` execution events.
- **Automatic Logging**:
    - **LLM Calls**: Recorded automatically to `agent_activity.llm_calls` (creating `LlmCall` records).
    - **Tool Calls**: Recorded automatically to `agent_activity.events` with `event_type: "tool_execution"`. Includes tool name, input (partial), and result preview.
    - **Tool Errors**: Recorded automatically to `agent_activity.events` with `event_type: "tool_error"`. Includes tool name, input, and error details.
    - **Final Status**: The `AgentActivity` status is updated to `finished` or `failed` in the `after_run` or `handle_run_error` hooks. The final output is stored in `agent_activity.output`.
- **Session Data (`@session_data`)**: This attribute now primarily holds the final `:output` of the agent run. Detailed trace information resides in the associated `AgentActivity` record.

**You do not need to manually log LLM calls or tool executions within your agent code if an `AgentActivity` is provided.**

## Job Integration (Solid Queue)

Agents are typically executed asynchronously using background jobs.

1.  **Create `AgentActivity`**: Before enqueuing, create an `AgentActivity` record to track the run.
    ```ruby
    activity = AgentActivity.create!(
      agent_type: MySpecialAgent.name,
      status: "queued",
      task_id: relevant_task&.id,
      # ... other relevant fields like parent_id ...
    )
    ```
2.  **Enqueue Agent Job**: Use the agent's `enqueue` class method, passing necessary options, including the `agent_activity_id`.
    ```ruby
    MySpecialAgent.enqueue(
      "Input prompt or description for the agent run",
      {
        task_id: relevant_task&.id,
        agent_activity_id: activity.id, # Pass the ID
        purpose: "Specific purpose for this run",
        # ... other options needed by the agent's initialize ...
      }
    )
    ```
3.  **Job Execution**: The corresponding `AgentJob` (e.g., `app/jobs/agents/agent_job.rb`) will typically:
    - Find the `AgentActivity` using the passed `agent_activity_id`.
    - Instantiate the agent (`MySpecialAgent.new(...)`), passing the `agent_activity` instance and other options.
    - Call `agent.run(...)`.

## Best Practices

1.  **Single Responsibility**: Design agents with clear, focused purposes.
2.  **Appropriate Model Selection**: Use `self.default_llm` or initialization options to configure the right LLM for the agent's tasks.
3.  **Effective Prompting**: Write clear, concise prompts for LLM interactions within chains or custom setups.
4.  **Rely on Automatic Logging**: Ensure `AgentActivity` records are created and associated for automatic tracing via the callback handler. Avoid manual logging of LLM/tool calls.
5.  **Robust Tool Design**: Create reliable tools. Handle errors gracefully within tool logic where possible. Tool errors are automatically logged by the callback handler.
6.  **Custom Tool Objects**: Prefer separate tool classes (`self.custom_tool_objects`) for complex or shared tools.
7.  **Configuration**: Use environment variables or Rails configuration for API keys or settings needed by tools or LLMs.

## Example Agent (Revised)

```ruby
# app/agents/web_search_agent.rb
class WebSearchAgent < BaseAgent
  # Uses a custom tool object for searching

  # Define Queue
  def self.queue_name
    :web_search
  end

  # Register Custom Tool Object
  # Assumes SerpApiSearchTool is defined elsewhere and implements Langchain::Tool::Base
  def self.custom_tool_objects
    # Configuration (e.g., API key) should ideally happen within the tool
    # or be passed via environment variables.
    [ SerpApiSearchTool.new ] # Register an instance
  end

  # No specific tools defined via self.tool block in this example

  # BaseAgent handles initialization and chain setup.
  # If custom_tool_objects are defined, BaseAgent will likely create a ToolChain.

  # The default `run` method from BaseAgent will execute the ToolChain,
  # which will use the LLM to decide when to call the SerpApiSearchTool.
  # Logging of LLM calls and tool usage is automatic via AgentActivityCallbackHandler.
end

# --- Enqueuing the job ---
# activity = AgentActivity.create!(agent_type: WebSearchAgent.name, status: 'queued', ...)
# WebSearchAgent.enqueue(
#   "Find recent news about AI agent frameworks.", # This becomes the input to agent.run
#   { agent_activity_id: activity.id, purpose: "Web search for AI frameworks" }
# )
```

## Advanced Patterns

Leverage the core structure for more complex scenarios:

1.  **Agents with Memory**: Pass memory objects (e.g., `Langchain::Memory::ConversationBufferWindowMemory`) during chain setup (`setup_chain!`) or initialization.
2.  **Multi-step Agents / Orchestration**: Use Coordinator agents (`CoordinatorAgent`, `ResearchCoordinatorAgent`) to break down tasks and assign subtasks to specialized agents using their respective `enqueue` methods.
3.  **Event-driven Workflows**: Utilize the `EventSubscriber` mixin and system-wide `Event.publish` calls to trigger agents based on system occurrences.
4.  **Retrieval-Augmented Generation (RAG)**: Provide a `retriever` during initialization. `BaseAgent`'s `setup_chain!` will attempt to create a `RetrievalQAChain`.