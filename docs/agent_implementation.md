# Agent Implementation Guide

## Overview: Regent Framework

**Regent** is a Ruby agent framework enabling composable, traceable AI agents that interact with LLMs and perform real-world actions via "tools." It is designed for transparency, debugging, and flexibility in agent orchestration, with built-in session tracing for every agent run.

**Key Concepts:**
- **Agent**: Encapsulates reasoning logic and tool usage, typically as a subclass of `Regent::Agent`.
- **Tool**: Discrete, callable actions available to agents, defined as Ruby methods or classes (inheriting from `Regent::Tool`).
- **Session**: Every agent run is traced, with all LLM calls, tool executions, and results recorded for debugging and replay.

## LLM Provider: OpenRouter Only

At this stage, the implementation is **restricted to OpenRouter** as the sole LLM backend. Regent's built-in support for OpenAI, Anthropic, Gemini, and Ollama is intentionally disabled or ignored for our use case.

**Requirements:**
- Set the `OPEN_ROUTER_API_KEY` environment variable with a valid OpenRouter API key. (THIS SHOULD BE SETUP ALREADY)
- Define some reasonable model_defaults for fast:, thinking:, multimodal:, edge: to use in our first agents
- When initializing an LLM, always use the OpenRouter provider:
  ```ruby
  model = Regent::LLM.new("openrouter/model-name")
  ```

## Solid Queue Integration for Agent Execution

**Orchestration Pattern:**
- Each agent/job type runs in its own Solid Queue queue for concurrency and isolation.
- Regent agents are wrapped inside Solid Queue jobs. When an event is published, enqueue the corresponding agent job on the correct queue.
- When a job completes, it can emit new events (by creating Event records or publishing to Regent/Solid Queue as appropriate).

### Example: Agent Job Setup

1. **Define a Regent Agent (in Ruby):**
    ```ruby
    class MyAgent < Regent::Agent
      tool :search_web, "Search for information on the web"

      def search_web(query)
        # Logic to perform web search
      end
    end
    ```

2. **Wrap the Agent in a Solid Queue Job:**
    ```ruby
    class AgentJob < ApplicationJob
      queue_as :my_agent_queue  # Unique queue per agent

      def perform(task_payload)
        agent = MyAgent.new("You are a research assistant", model: Regent::LLM.new("openrouter/your-model"))
        agent.run(task_payload)
        # Optionally: emit events, update domain models, etc.
      end
    end
    ```

3. **Enqueue by Event/Trigger:**
    ```ruby
    AgentJob.set(queue: :my_agent_queue).perform_later("Find the latest weather for Tokyo")
    ```

### Solid Queue Best Practices
- **Queue Naming:** Use a distinct queue name per agent/job type (e.g., `:orchestrator_agent_queue`, `:summarizer_agent_queue`).
- **Concurrency:** Set queue-specific concurrency limits in Solid Queue config to control parallelism per agent type.
- **Event Bridging:** On job completion, publish new events by either enqueuing further jobs or creating Event records for Rails/reactive dashboards.

### ENV and Dependency Checklist

- [ ] `gem "regent", github: "estiens/regent"` in your Gemfile.
- [ ] `gem "open_router"` in your Gemfile.
- [ ] Set `OPEN_ROUTER_API_KEY` in the environment.
- [ ] No other LLM API keys are needed.

### Troubleshooting

- If a Regent agent raises an API key error, confirm that `OPEN_ROUTER_API_KEY` is correctly set.
- Review session traces for any failed tool or LLM calls (Regent provides detailed step logs).

---

## Summary

- Regent is the core agent orchestration and reasoning framework.
- All LLM calls must go through OpenRouter for now.
- Each agent/job type gets its own Solid Queue queue for concurrency and isolation.
- Events and jobs are bridged by wrapping agents in jobs and emitting events at job boundaries.

For additional reference, see the Regent [README](../regent/README.md) and the main workplan.