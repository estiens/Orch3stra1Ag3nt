# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build/Test Commands
- Start dev server: `bin/dev` or `foreman start -f Procfile.dev`
- Run all tests: `bundle exec rspec`
- Run single test: `bundle exec rspec path/to/spec.rb:LINE_NUMBER`
- Run specific test file: `bundle exec rspec spec/path/to/spec.rb`
- Lint code: `bundle exec rubocop`
- Fix auto-correctable issues: `bundle exec rubocop -a`

## Code Style Guidelines
- Ruby style: Uses Rails Omakase style (standard Rails conventions)
- State machines: Use AASM gem for Task and AgentActivity models
- Agent code: Keep in app/agents directory with clear separation of concerns
- Error handling: Log errors properly and use the ErrorHandler service
- Naming: Follow Rails conventions (snake_case variables/methods, CamelCase classes)
- Testing: Use RSpec, FactoryBot, and VCR for API interactions
- Agents should be modular, reusable, and communicate via EventBus
- Agent operations must use DB models and callbacks

## Architecture Notes
- LangChain.rb (Ruby gem) provides LLM abstractions and JSON Schema validation
- Event-driven system with pub/sub communication between agents
- All agent execution is asynchronous via background jobs (Solid Queue)
- Full observability with extensive logging and real-time dashboard
- HITL (Human-In-The-Loop) pattern for complex decisions

## Core Models
- Task: Top-level work unit with state machine
- AgentActivity: Agent executions with parent/child relationships
- LlmCall: Every LLM interaction with request/response details
- Event: System-wide event bus for inter-agent communications

## Event System Migration
- Event system is transitioning from legacy EventBus to RailsEventStore
- When publishing events, use EventService.publish instead of Event.publish
- Event types use dot notation (e.g., "agent.started" instead of "agent_started")
- Use EventMigrationExample as a guide for updating event publishing code
- Event handlers should implement the call(event) interface for RailsEventStore