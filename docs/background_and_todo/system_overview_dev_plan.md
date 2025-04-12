Switching gears to Rails 8 as your foundational architecture is a very strong and pragmatic move—especially for the multi-agent, event-driven, highly observable system you’re envisioning. Here’s how Rails can amplify your design, caveats on complexity, and a nuanced techspec update based on this new “Rails-native” approach.


Why Rails 8 is a Smart Choice

1. Familiar, Productive Framework


    Rails is widely known, making it easier to onboard contributors.

    You get the full power of ActiveRecord, native model validations, ActionCable, Turbo, and all the other conventions.

    Rapid scaffolding of new agent types, event models, admin panels, and dashboards.


2. First-Class Job System


    ActiveJob (with async queue backends like Sidekiq, GoodJob, or Que) allows you to spawn agents as jobs—giving massive resilience, visibility, and failure recovery “for free.”

    Failed jobs can be retried, paused, or manually intervened.


3. Turbo Streams, ActionCable, Built-in Realtime UX


    Rails 8 + Turbo Streams enable rich, real-time event dashboards and on-the-fly notification of HITL events without extra infra.

    All events and state changes can be streamed to browsers or admin consoles without external pub/sub.


4. Observability and Admin UIs


    Use Rails Admin, ActiveAdmin, or custom dashboards to surface every event, LLM call, task/lifecycle, with filtering & history.

    Quick to build out audit trails, approval/rejection, and HITL response panels.


5. Predictable State Machine Modeling


    Use gems like aasm or state_machines-activerecord to model Task, AgentActivity, and Agent/LlmCall state, ensuring explicit transitions, guards, and error hooks tied to the DB.


6. Service-Driven Structure


    Most agent logic can (should) live in app/services/agents/—use Rails for orchestration, monitoring, and data; keep agentic business logic isolated and testable.



Potential Pitfalls & Mitigations


    The “Thundering Herd”:
        Rails/Job-system makes it absurdly easy to spawn tons of agents (jobs), which can overload your infra/database if runaway loops/bugs occur.
        Mitigation: Always implement rate limits, depth guards, and recursion/chain limits (see below). Use built-in queue monitoring to halt problem jobs.

    Complex Event Graphs:
        With jobs-as-agents, complex flows can get hard to debug without good event modeling.
        Mitigation: Treat every “AgentActivity” as a DB model (with parent/child, ancestry, etc.), and surface their status/relationships in the dashboard.



Updated Techspec — With Rails 8 Backbone

1. Core Models


    Task: Top-level unit; has a state machine (e.g., pending, active, waiting_on_human, completed, failed).

    AgentActivity: Each “agent” spawn/subtask, with parent/child relationships to reconstruct flows.

    LlmCall: Each interaction with an LLM/tool, with full request/response payloads, duration, cost.

    Event: All meaningful events (errors, retries, human requests, completions, etc.).


2. Job System as Agent Execution Layer


    Each agent is implemented as a job (app/jobs/agents/).

    Use job arguments for agent type, context, task ID, etc.

    All agent operations live in jobs; side effects (state changes, LLM calls, child agent spawning) always go through DB models and well-defined callbacks.


3. Observability & Dashboard


    Built-in Rails or ActiveAdmin

    for Event, Task, AgentActivity, LlmCall.

    Turbo Streams or ActionCable for live event/HITL notification to the browser.

    Optional: time series visualizations for task/agent volume, error rates.


4. HITL (Human-in-the-Loop) Events


    Soft and Hard events are rows in Event, tied to AgentActivity (and optionally Task).

    Hard events pause the Task/Agent state machine; require a user/admin action (ideally from a live UI via Turbo, TurboFrame, or similar).

    Soft events show as notifications, auto-dismiss or escalate if ignored.


5. State Machine Guards


    Use AASM

or state_machines-activerecord

    for Task and possibly AgentActivity.

    On state transitions (e.g., to errored), define guards/hooks for side effect control and event emission.


6. Error Handling & Thundering Herd Control <a name="preventing-runaway-spawn"></a>


    Always specify max parallelism/spawn depth per Task (e.g., via model attributes/config).

    Implement circuit-breaker triggers: if one agent spawns too many sub-agents, auto-halt or escalate for human review.

    Use background job queue monitors (e.g., Sidekiq dashboard) and custom “ActiveAlert” events if job queues grow abnormally.


7. Service and Schema Layer


    Keep agent logic in app/services/agents/, use dry-types, dry-schema, and dry-validation for all inter-agent events and LLM/tool calls (medium.com

    ).

    Each event/interaction is a strongly-typed, auditable database row.


8. Realtime/Vector Search (Optional)


    ActiveRecord for all persistence; can use vector

extension (pgvector), or supplement with Qdrant/Milvus as described in medium.com, github.com

    .

    Dashboard listens to changes via Turbo Streams.



Suggested Gems & Libraries


    State machines: AASM

    Background jobs: SOLID_QUEUE

    Vector search: pgvector, (add to rails database)

Schema/type validation: dry-types, dry-schema, dry-validation

Realtime UI: ActionCable, Turbo Streams ???

Dev/test: rspec-rails, factory_bot_rails

LLM/AI: open_router



Final Thoughts


    Rails 8 gives you unrivaled leverage for DB-backed observability, developer productivity, real-time dashboards, and strong job/queue/resource management.

    Modeling agents as jobs and activities as models/events gives you clarity, history, and auditability.

    Guard against runaway behavior using ALL of Rails/Sidekiq’s queue monitoring, state guards, and circuit-breakers; this is by far the biggest operational risk in dynamic agent systems.

    You can keep your agent/business logic portable: most agent “brains” live in services, just invoked from jobs.

    I'm thrilled to hear that this system will be bootstrap-dogfooded into existence using agents for coding and code review alongside the orchestrator. That’s a fascinating meta-approach and aligns perfectly with the modular, agent-driven design we’re crafting. I’ll address your thoughts on the OrchestratorAgent lifecycle (short-lived vs. long-running) and the benefits of queue-specific management with tools like Sidekiq or Solid Queue (new to Rails 8). I’ll incorporate your ideas about queue prioritization, limits, cancellation, and reprioritization into the design. Following that, I’ll rewrite the entire technical specification from top to bottom as requested, ensuring it’s cohesive and detailed, while factoring in the bootstrapping context for future agent-driven development.

Thoughts on OrchestratorAgent Lifecycle and Queue Management


    OrchestratorAgent Lifecycle: I agree that having the OrchestratorAgent as a short-lived, event-triggered entity rather than a long-running job makes sense for several reasons. It reduces resource consumption by only existing when needed (e.g., at system startup, task initialization, or task completion for review). It also aligns with the granular, event-driven philosophy of "everything as an agent," where even orchestration is a transient, purpose-driven task. The OrchestratorAgent can be spawned by a recurring Sidekiq/Solid Queue job or event listener (e.g., on TaskCompleted or system startup), perform its duties (review progress, switch directions, spawn CoordinatorAgents), and terminate. This approach avoids a single point of failure or memory bloat from a long-running process and allows for easier updates to orchestration logic by respawning with fresh configurations.

    Queue-Specific Management with Limits and Prioritization: Using Sidekiq or Solid Queue (Rails 8’s new built-in queue system) to assign each agent type its own queue (e.g., :orchestration, :web_scraping, :research) is a powerful idea. It enables fine-grained control over concurrency limits (e.g., max 10 WebScrapingAgents via :web_scraping queue limit), prioritization (e.g., :orchestration queue has highest priority to ensure timely reviews), and dynamic management. Allowing the OrchestratorAgent to cancel entire queues (e.g., abandon a task by clearing :research queue for a deprecated workflow) or reprioritize queues (e.g., boost :summarization over :web_scraping if summaries are urgent) adds significant flexibility. Solid Queue, being tightly integrated with Rails 8 and PostgreSQL, offers simplicity and database-backed reliability over Sidekiq (which requires Redis setup), though Sidekiq’s maturity and UI might be preferable for visibility during bootstrapping.

    Recommendation: Let’s adopt a short-lived OrchestratorAgent spawned by events or scheduled jobs (e.g., via Solid Queue recurring tasks in Rails 8), with queue-specific management for agents. Use Solid Queue initially for tighter Rails integration, with the option to switch to Sidekiq if advanced monitoring (via its UI) is needed during dogfooding. The OrchestratorAgent will have privileged control over queues (cancellation, reprioritization) implemented via queue API interactions within Rails, ensuring it can pivot system direction dynamically.


Now, let’s rewrite the technical specification from top to bottom, incorporating these updates, the Rails 8 context, and the bootstrapping intent for agent-driven development.


Technical Specification: Multi-Agent Event-Driven AI Framework in Rails 8

1. Introduction and Objectives

This specification outlines a multi-agent, event-driven AI framework built within a Rails 8 application to support dynamic workflows such as research systems with orchestration, planning, and task-specific processing. The system is designed to be bootstrap-dogfooded, where initial agents (e.g., coding and code review agents) and the orchestrator will iteratively develop and refine the framework itself based on this spec. Key objectives include:


    Modularity: Implement all functionality as granular agents (e.g., OrchestratorAgent, WebScrapingAgent), with sub-agents for intent-based delegation.

    Event-Driven Design: Leverage Regent for core publish/subscribe messaging, integrated with Rails event mechanisms for persistence and UI updates.

    Parallelism: Use Ruby 3+ Ractors for agent isolation and parallelism, managed via Rails 8 job queuing (Solid Queue or Sidekiq).

    Human-in-the-Loop (HitL): Enable soft and harsh clarification events for agent or system-wide human intervention.

    LLM Logging: Persist every LLM interaction (e.g., OpenRouter calls) for transparency, cost tracking, and debugging.

    Dashboard: Provide real-time monitoring via Rails views with Turbo Streams for agent activity, costs, errors, progress, deliverables, and LLM logs.

    Validation and Typing: Enforce strict schemas with Dry-Schema, Dry-Types, Dry-Validation alongside Rails model validations.

    Scalability and Control: Manage agent execution via queue-specific job systems (Solid Queue/Sidekiq) with limits, prioritization, and dynamic cancellation/reprioritization to prevent runaway complexity.


2. Rationale for Rails 8

Rails 8 provides a robust, familiar foundation for this framework, ideal for iterative development during bootstrapping by agent-driven coding and review:


    Infrastructure: Built-in ActiveRecord (PostgreSQL), job queuing (Solid Queue), and real-time UI (Turbo Streams) simplify persistence, async processing, and monitoring.

    Familiarity: Well-known to the primary developer and community, easing extension and collaboration during dogfooding.

    Complexity Management: Rails conventions (models, services, jobs) structure the system as agent counts and interactions grow, with job queue visibility to prevent issues like runaway spawns (e.g., 50 agents spawning 50,000).

    Ecosystem: Vast gem library for integrating tools (e.g., web scraping, vector databases) into agents.


3. Core Architecture

3.1 Agents as Fundamental Units


    Definition: Every component is an Agent, implemented as a Ruby service class under app/services/agents/ in Rails, ranging from high-level orchestration to task-specific sub-agents. Agents are stateless or stateful, short-lived or triggered by events.

    Agent Types:
        High-Level: OrchestratorAgent (system-wide control, short-lived), CoordinatorAgent (task ownership and delegation).
        Task-Specific: ResearchAgent, WebScrapingAgent, SummarizerAgent, OpenRouterCallAgent (LLM interactions).
        Sub-Agents: Delegated for detailed tasks (e.g., VectorDatabaseStorageAgent, interpreting high-level intent).
        Meta-Agents: ErrorHandlerAgent (error recovery), RoutingAgent (task rerouting), ResourceMonitorAgent (system limits), LlmLogAgent (LLM logging).

    Lifecycle: Agents are spawned as asynchronous jobs via Rails’ job system (Solid Queue by default in Rails 8, with Sidekiq as an alternative), terminating upon task completion if short-lived. Ractors provide parallelism within jobs for isolation (e.g., multiple WebScrapingAgents).

    Behavior: Agents encapsulate logic (e.g., retries, decision-making) and delegate complex tasks to sub-agents via intent-based events, avoiding overload of parameters or tools.


3.2 OrchestratorAgent Lifecycle


    Short-Lived Design: The OrchestratorAgent is not a long-running job but spawns transiently for specific purposes: system initialization, task creation, progress review upon main task completion, or strategic redirection. It is triggered by events (e.g., TaskCompleted, SystemStartup) or a recurring Solid Queue job (e.g., every 5 minutes to check system state).

    Responsibilities: Reviews system progress, spawns CoordinatorAgents for new tasks, switches workflow directions, and manages job queues (e.g., cancel, reprioritize).

    Advantages: Reduces resource usage by only existing when needed, avoids persistent state issues, and allows updates to orchestration logic via respawn with fresh configs.


3.3 Queue-Specific Management with Solid Queue/Sidekiq


    Queue Assignment: Each agent type is assigned a unique queue (e.g., :orchestration, :web_scraping, :research, :summarization) managed by Solid Queue (Rails 8 native, PostgreSQL-backed) or Sidekiq (Redis-backed with mature UI).

    Concurrency Limits: Queue-specific limits prevent overload (e.g., max 10 concurrent WebScrapingAgents on :web_scraping queue, max 5 ResearchAgents on :research queue), configured in Rails job setup.

    Prioritization: Queues have configurable priorities (e.g., :orchestration at highest priority to ensure timely reviews, :summarization over :web_scraping if summaries are urgent), adjustable dynamically by OrchestratorAgent.

    Cancellation and Reprioritization: OrchestratorAgent has privileged access to job queue APIs (via Solid Queue/Sidekiq) to cancel entire queues (e.g., clear :research if task is obsolete) or reprioritize queues (e.g., elevate :summarization priority mid-workflow).

    Implementation Choice: Start with Solid Queue for seamless Rails 8 integration and PostgreSQL consistency during bootstrapping. Consider Sidekiq if advanced monitoring UI is needed for agent-driven development visibility.


3.4 Event Bus Integration


    Core Mechanism: Regent powers the primary publish/subscribe event bus for agent communication, ensuring loose coupling.

    Rails Integration: ActiveSupport::Notifications instruments Regent events for Rails logging and bridges to Turbo Streams for real-time dashboard updates.

    Event Types:
        Task-Related: TaskAssigned, TaskCompleted, DeliverableComplete.
        Progress/Error: ProgressUpdate, ErrorReport.
        LLM-Specific: LlmRequestSent, LlmResponseReceived.
        HitL: SoftClarificationRequest (continue unless responded), HarshClarificationRequest (halt until response), SystemHaltForClarification (system-wide pause).

    Event Handling: Regent events trigger agent actions (as jobs) and persist updates to Rails models (e.g., Task state changes). An optional EventFilterAgent (job on :event_filter queue) aggregates frequent events to reduce dashboard/log noise.


3.5 Human-in-the-Loop (HitL) Events


    Purpose: Allow agents or system to request human intervention for ambiguous or critical decisions.

    Types and Behavior:
        Soft Clarification Request: Agent emits event and continues unless human responds (via ClarificationResponse event). Timeout configurable (e.g., proceed after 30 minutes if no input).
        Harsh Clarification Request: Agent halts task (pauses job via Solid Queue) until ClarificationResponse received.
        System-Wide Halt: OrchestratorAgent emits SystemHaltForClarification, pausing all queues via job system API until SystemResume event with human input.

    Rails Integration: HitL events create ClarificationRequest model records in PostgreSQL, displayed on dashboard via Turbo Streams. Human input (via form) updates the model and resumes jobs.

    Notifications: Harsh and system-wide requests trigger external alerts (e.g., ActionMailer email, Slack via gem) for timely response.


3.6 Parallelism and Job Execution


    Ractors: Ruby 3+ Ractors enable parallelism within Solid Queue jobs for agents requiring isolation (e.g., multiple WebScrapingAgents scraping concurrently).

    Fibers: Handle I/O-bound operations (e.g., OpenRouter API calls) within Ractors/jobs to prevent blocking.

    Job System: Solid Queue spawns agents as async jobs on type-specific queues, with built-in retries, timeouts, and visibility to monitor execution.

    Runaway Spawn Safeguards: Queue concurrency limits, ResourceMonitorAgent (recurring job on :resource_monitor queue monitoring job counts and system load), and RoutingAgent (detecting spawn loops via event patterns) prevent scenarios like 50 agents spawning 50,000. OrchestratorAgent can cancel queues or trigger system-wide halts if thresholds are breached.


3.7 LLM Interaction and Logging


    Agent Execution: OpenRouterCallAgent (job on :llm_call queue, max concurrency e.g., 5) handles each LLM interaction, validates input/output with Dry-Schema, and emits events (LlmRequestSent, LlmResponseReceived).

    Persistence: Every call/response is saved as an LlmCall model in PostgreSQL (via ActiveRecord), capturing full request/response data and metadata (e.g., cost, latency).

    Logging Agent: LlmLogAgent (job on :llm_log queue) ensures persistence and summarizes stats for dashboard.

    Error Handling: Validation failures spawn FixResponseAgent (job on :fix_response queue) to re-prompt or escalate via HitL.


3.8 Dashboard and Monitoring


    Implementation: Rails controllers/views under app/controllers/dashboard/ render metrics, logs, and interaction points.

    Real-Time Updates: Turbo Streams (Turbo gem in Rails 8) push updates for agent counts, job queue statuses, LLM stats, errors, deliverables, and HitL requests without page reloads.

    Features:
        Active agents and queue stats (e.g., via Solid Queue insights or Sidekiq UI if used).
        LLM metrics (total calls, costs, error rates) from LlmCall model.
        HitL interface with forms for responding to clarification requests.
        Deliverables and filtered error logs.

    System Logs: Rails’ built-in logging (via lograge for cleaner output) to file or external service, separate from agent-reported errors on dashboard.


3.9 Typing and Validation


    Dual Validation: Dry-Schema, Dry-Types, Dry-Validation for strict agent/event schemas; Rails ActiveRecord validations for model data integrity.

    Configuration: strict_schema flag toggles runtime validation strictness (default: true).

    Correction: FixResponseAgent resolves schema failures dynamically.


3.10 Persistence and Models


    PostgreSQL via ActiveRecord: Structured storage for key entities as Rails models:
        AgentActivity: Historical log of agent spawns/terminations/statuses (optional for analysis).
        LlmCall: Full log of LLM interactions (request, response, metadata).
        Task: Workflow tasks with state, owner agent, associations (e.g., sub-tasks, LlmCalls), deliverables.
        ClarificationRequest: HitL requests with type (soft/harsh), status, response.

    State Machine: Task model uses state_machine gem for states (e.g., pending, in_progress, awaiting_clarification, completed) with guards (e.g., block on harsh HitL) and side-effects (e.g., trigger events/jobs on transition).

    Redis (Optional): Ephemeral cache for high-frequency state (e.g., active queue counts) if PostgreSQL writes bottleneck.

    Research Data: Vector databases/document stores managed by agents like VectorDatabaseStorageAgent, with metadata in PostgreSQL.


4. Workflow Example (Research System with Rails 8)


    System Start: Recurring Solid Queue job spawns OrchestratorAgent (on :orchestration queue, highest priority) to initialize workflow, creating a Task model (state: pending).

    Task Delegation: OrchestratorAgent spawns CoordinatorAgent (on :coordination queue), updates Task state (in_progress), terminates.

    Planning: CoordinatorAgent emits PlanResearch event, spawning PlanningAgent (on :planning queue), which breaks task into questions, logged as AgentActivity (if enabled).

    Parallel Execution: PlanningAgent emits ResearchQuestion events, spawning multiple ResearchAgents (on :research queue, max 5 concurrent) as jobs with Ractors.

    Sub-Agent Delegation: A ResearchAgent spawns WebScrapingAgent (on :web_scraping queue, max 10 concurrent) for data collection, potentially emitting HarshClarificationRequest if blocked (e.g., paywall), pausing job and creating ClarificationRequest model.

    Human Input: Dashboard (updated via Turbo Stream) shows request; human responds, updating ClarificationRequest, triggering ClarificationResponse event, resuming job.

    Completion Review: ResearchAgents complete sub-tasks, update Task state, emit TaskCompleted, triggering OrchestratorAgent respawn to review progress, reprioritize queues (e.g., elevate :summarization), or cancel obsolete queues (e.g., clear unused :web_scraping jobs).

    LLM Logging: Each OpenRouterCallAgent job persists interactions to LlmCall model, visible on dashboard.


5. Safeguards Against Runaway Complexity (50 Agents to 50,000)

To prevent unintended agent proliferation or spawn loops, especially critical during bootstrap-dogfooding with coding/review agents:


    Queue Concurrency Limits: Solid Queue/Sidekiq enforces max jobs per queue (e.g., 10 for :web_scraping, 5 for :research), configurable in Rails.

    ResourceMonitorAgent: Recurring job (on :resource_monitor queue) tracks active job counts, system load (via sys-cpu gem), emits alerts or triggers SystemHaltForClarification if thresholds breached (e.g., >50 total agents).

    RoutingAgent: Analyzes event patterns (on :routing queue) for spawn loops (e.g., rapid TaskAssigned bursts), instructing OrchestratorAgent to cancel queues or pause workflows.

    Task Model Guards: Task state machine limits sub-task depth or count (e.g., max 10 per parent), prevents recursive creation without approval.

    Dashboard and Job UI: Real-time visibility via Turbo Streams and Solid Queue/Sidekiq UI to spot spikes manually.

    Circuit Breakers: Global halt mechanisms (via OrchestratorAgent) pause all queues if anomalies detected, requiring HitL resolution.


6. Technical Dependencies


    Core Rails Framework:
        rails (~> 8.0): Web framework for structure, persistence (ActiveRecord), jobs (Solid Queue), real-time UI (Turbo Streams).
        solid_queue: Rails 8 native job system for async agent execution, PostgreSQL-backed (Sidekiq alternative if UI needed).
        regent: Event-driven pub/sub for agent communication.
        dry-schema, dry-types, dry-validation: Strict typing for events and data.
        state_machine: State transitions for Task model with guards and side-effects.

    Database and Cache:
        pg: PostgreSQL adapter for ActiveRecord.
        redis (optional): Ephemeral state or Sidekiq backend if needed.

    Dashboard and Real-Time:
        turbo-rails: Turbo Streams for reactive UI updates on dashboard.
        chartkick: Charts for agent metrics, LLM costs on dashboard.

    Error Handling and Notifications:
        rollbar or sentry-raven: Error tracking for system issues.
        slack-notifier: Alerts for harsh HitL or system halts via Slack.


7. Suggested Gems for Agent Tools

These gems can be integrated by task-specific agents for specialized functionality, wrapped in service classes under Rails:


    Web Scraping/HTTP: httparty (HTTP client), nokogiri (HTML parsing), mechanize (browser automation for WebScrapingAgent).

    Text Processing: treat (NLP for SummarizerAgent), ruby-openai (adaptable to OpenRouter for text generation).

    Vector Databases: pgvector (PostgreSQL vector similarity for VectorDatabaseStorageAgent), redis-rb with redisearch (lightweight vectors).

    Document Storage: mongoid (MongoDB for documents), carrierwave (file storage to local/cloud).

    Monitoring/Notifications: pusher (real-time fallback if Turbo insufficient), slack-notifier (HitL alerts).

    Utilities: dotenv (environment variables for API keys), yaml (config for agent limits/behaviors).


8. Trade-Offs and Considerations


    Rails 8 Overhead: Adds startup/memory cost over lightweight Ruby, mitigated by focusing logic in services and jobs, deferring full-stack features (e.g., complex views) until needed.

    Event Bus Tension: Regent as primary event system may overlap with Rails’ ActiveSupport::Notifications; mitigated by clear separation (Regent for agents, Notifications for Rails integration).

    Queue System Choice: Solid Queue offers Rails 8 simplicity with PostgreSQL; Sidekiq provides richer UI for monitoring during bootstrapping. Start with Solid Queue, evaluate Sidekiq if visibility lacks.

    Short-Lived Orchestrator: Transient OrchestratorAgent reduces resource use but requires robust event/listener setup to ensure timely respawns; recurring jobs mitigate this risk.

    Bootstrapping Complexity: Agent-driven coding/review (e.g., PR agents) may introduce errors in early system builds; tight HitL integration and dashboard visibility address this.


9. Implementation Roadmap (Tailored for Bootstrap-Dogfooding)

Given the system will be built iteratively by agents (coding, code review) and orchestrator:


    Phase 1: Rails Core Setup:
        Initialize Rails 8 app with PostgreSQL, Solid Queue, Regent.
        Define base Agent service as job class, integrate Ractors.
        Set up Task, LlmCall models with state machine.

    Phase 2: Initial Agents for Bootstrapping:
        Implement short-lived OrchestratorAgent (triggered by recurring job/event), CoordinatorAgent, coding/review agents (e.g., CodeAgent, ReviewAgent).
        Configure queue-specific limits/priorities (e.g., :orchestration highest).

    Phase 3: Dashboard and HitL for Human Oversight:
        Build basic dashboard with Turbo Streams for metrics, HitL interaction during coding/review iterations.
        Add HitL events, ClarificationRequest model, job pausing/resumption.

    Phase 4: Task-Specific Agents and Resilience:
        Expand to ResearchAgent, WebScrapingAgent, etc., with sub-agent delegation.
        Add meta-agents (ResourceMonitorAgent, RoutingAgent) for spawn control, tested by coding agents’ PR workflows.

    Phase 5: Queue Management and Optimization:
        Enable OrchestratorAgent queue cancellation/reprioritization, validated by review agents.
        Optimize job concurrency, Ractor usage, dashboard metrics for scale.


10. Bootstrapping and Dogfooding Strategy


    Initial Focus: Early agents (CodeAgent, ReviewAgent) and OrchestratorAgent use this spec to build out remaining components, starting with minimal viable queues (e.g., :orchestration, :coding, :review).

    HitL Criticality: Tight human oversight via dashboard for coding/review errors, with frequent soft/harsh clarification requests to refine agent logic.

    Iterative Spec Updates: OrchestratorAgent and review agents update this spec (via PRs) as system evolves, ensuring documentation aligns with agent-built reality.

    Spawn Control Testing: Early stress tests by coding agents (e.g., simulate runaway loops) validate ResourceMonitorAgent and queue limits before broader agent types are added.



