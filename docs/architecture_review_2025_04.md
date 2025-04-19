# Architecture Review & Model Decisions (April 2025)

## Summary

This document captures the current state of the core models, recent architectural decisions, and open questions for future refactoring, especially as we move toward a more robust pub/sub event system.

---

## 1. AgentActivity Model: Decision & Rationale

**Decision:**  
We will keep `AgentActivity` as a separate model, strictly joined to `Task` via `task_id` (`belongs_to :task`).  
All agent execution state and history will be accessed through the parent `Task`.  
We will not pass both `Task` and `AgentActivity` around; all logic starts from `Task`.

**Rationale:**  
- A `Task` always spawns its own agent, and no other agent can ever work on it.
- This enforces a clear one-to-many (or one-to-one for most cases) relationship: `Task has_many :agent_activities`.
- Retains the ability to track agent execution history (retries, failures, restarts) per task.
- Avoids the complexity and performance issues of embedding activities as JSONB.
- All related models (LlmCall, Event, HumanInputRequest) are always joined through `Task` (never globally via AgentActivity).

---

## 2. Human-in-the-Loop (HITL) Models: Consolidation Needed

**Current State:**  
- There are two models for HITL: `HumanInputRequest` and `HumanIntervention`.
- Their boundaries and responsibilities are not always clear, leading to potential confusion and duplicated logic.

**Next Steps:**  
- Consolidate these into a single, unified HITL model or clearly define their separate roles.
- Ensure the new model supports both "soft" (routine clarification) and "harsh" (critical intervention) HITL flows.
- Update UI and workflows accordingly.

---

## 3. Event System Update

**Completed Implementation:**
- Successfully migrated from the overloaded Event model to RailsEventStore for pub/sub functionality
- Created a proper domain event system with explicit event classes and validation
- Implemented event streaming with clear aggregation by task, agent activity, and project
- Established consistent event naming convention using dot notation (e.g., "agent.started")
- Built backward compatibility layer to support gradual transition

**Key Components:**
- **BaseEvent**: Core class that all domain events inherit from
- **EventService**: Central service for publishing events to the system
- **Domain-specific Event Classes**: Strongly typed events with proper schemas (AgentEvents, ToolEvents, SystemEvents)
- **Event Handlers**: Dedicated handlers that implement the call(event) interface
- **Event Streams**: Events are organized into streams based on their context (task streams, agent streams, project streams)

**Benefits Realized:**
- Reduced coupling between components
- Improved testability with better separation of concerns
- Enhanced ability to reason about event flow
- Stronger type safety and validation
- Simplified event publishing and subscription
- Better observability and debugging capabilities

**Configuration:**
- Legacy Event records can still be created for backward compatibility
- Configuration option to disable legacy records when ready

**Next Steps:**
- Update tests to use the new event system
- Set Rails.configuration.create_event_records = false in production once confirmed stable
- Consider performance optimizations for high-volume event processing

---

## 4. Open Questions

- What is the best way to consolidate HITL models for both routine and critical interventions?
- How should we optimize event handling for high-volume scenarios?
- Should we implement event versioning for better forward compatibility?

---

## 5. Next Steps

- Proceed with keeping `AgentActivity` as a strictly task-scoped model.
- Begin consolidation of HITL models.
- Complete the event system transition by updating tests and enabling the pure RailsEventStore mode in production.
- Consider event versioning for future-proofing the system.
- Implement performance monitoring and optimizations for high-volume event scenarios.

---

*This document will be updated as architectural decisions evolve. See also: `.clinerules/rails_multi_agent_system.clinerule` and `app/architechture_overview.md` for further context.*
