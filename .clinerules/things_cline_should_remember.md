# things_cline_should_remember.clinerule

## Process & Workflow

- Always read docs in `background_and_todo` before starting new work.
- Update todo.md, notes_to_self, or open_questions as you discover new tasks or architectural changes.
- For significant architecture, always add or update a tech spec in `background_and_todo`.
- Start each todo item by making a new git branch; mark as pending until the branch is finished.
- Human In The Loop (HITL) marks todos as completed when merged to main.

## Core Architectural Principles

- Maintain strict separation of concerns: models, agent logic, tools, and infrastructure services.
- Keep agents and tools modular, reusable, and event-driven.
- All agent execution should be asynchronous via background jobs (Solid Queue/Sidekiq).
- Use state machines for Task and AgentActivity models.
- Log all agent actions, tool invocations, and LLM calls for traceability.
- Implement and use a true event bus (Regent) for inter-agent communication, not just logging.
- All agent operations (state changes, LLM calls, child agent spawning) must go through DB models and callbacks.

## Testing & Validation

- Prefer fixing specs to changing implementation unless the implementation is clearly wrong.
- Increase test coverage for agents, tools, and error handling; use mocks/stubs for external dependencies.
- Validate all LLM/tool responses; escalate or auto-fix on validation failure.

## LangChain.rb & JSON Schema Validation

- The system uses the [langchainrb Ruby gem](https://github.com/andrewmcodes/langchainrb) (not the Python framework).
- langchainrb provides built-in JSON Schema validation for tool and agent interactions.
- If validation or tool integration isn't working as expected, review the [langchainrb documentation](https://github.com/andrewmcodes/langchainrb) for guidance and updates.

## Tooling & Abstraction

- Extract tools into standalone classes; avoid embedding tool logic in agents.
- Create and maintain a dynamic tool registry for discovery and configuration.
- Refactor duplicated logic in tools into shared modules or concerns.
- Define explicit interfaces or base classes for tools.

## Human-in-the-Loop (HITL)

- Implement both soft and harsh clarification events; jobs should pause/resume as appropriate.
- Build a dashboard for HITL events and allow human responses via UI.
- Add timeout handling and escalation for HITL requests.

## Observability & Dashboard

- Scaffold a real-time dashboard using Turbo Streams for agent/job stats, LLM metrics, and HITL events.
- Integrate event logging with Rails logs and dashboard.
- Monitor job queues and system health; add cost tracking and visualization.

## Safeguards & Scaling

- Assign unique queues for each agent type; enforce concurrency and spawn depth limits.
- Implement circuit-breakers and ResourceMonitorAgent to prevent runaway spawns.
- Use Redis for ephemeral state if needed; plan for large context persistence.
- Simulate runaway agent scenarios to validate spawn control.

## Areas for Improvement

- Add inline code comments and method-level documentation, especially for complex agent-tool interactions.
- Consider splitting overloaded models (e.g., AgentActivity) as the system grows.
- Implement retry strategies, exponential backoff, and global error monitoring/alerting.
- Integrate vector database/document storage for semantic search.

## General

- Keep agent/business logic portable, testable, and isolated in services.
- Update documentation and specs iteratively as the system evolves.
- Leverage latest LangChain.rb features for workflow and tool abstraction.
- Standardize agent lifecycle hooks in BaseAgent.
- Document event types and consider a typed event system.
