# Model Overview

This document provides an overview of the Rails models in the `models` directory and their relationships. The models are designed to support an AI-powered agent system, handling projects, tasks, agent activities, human input requests, LLM calls, vector embeddings, and events.

## Model Diagram (Conceptual)

*   `Project` is the central entity, containing many `Task` and `VectorEmbedding` records.
*   `Task` is composed of many `AgentActivity` records.
*   `AgentActivity` can trigger `HumanInputRequest` and/or can result in `LlmCall` entries.
*   All models (except `ApplicationRecord`) include the `Contextable` concern to make project, task and/or agent_activity context easily available on each record.
*   Many models include `EventPublisher` to publish events when certain actions occur (e.g. creation, update).
*   `Event` records can be associated with `AgentActivity` or can be system-level spanning tasks/projects.

## Model Descriptions

### 1. `ApplicationRecord` (`application_record.rb`)

*   **Purpose**: This is the base class for all models in the application, inheriting from `ActiveRecord::Base`. It provides a central point for configuring application-wide model behavior.
*   **Architecture**: It's an abstract class, meaning no database table is directly associated with it.

### 2. `Project` (`project.rb`)

*   **Purpose**: Represents a project that the AI agent is working on. It defines the overall goals, settings, and status of the project.
*   **Attributes**:
    *   `name`: The name of the project (string).
    *   `description`: A description of the project (text).
    *   `status`: The current status of the project (string, e.g., "pending", "active", "completed").
    *   `settings`: JSONB column for project settings (e.g., LLM budget, task timeout).
    *   `metadata`: JSONB column for storing project metadata (e.g., pause time).
    *   `priority`: Determines the order the project should be processed in (integer).
*   **Associations**:
    *   `has_many :tasks`:  A project can have many tasks. Deleting a project also deletes its tasks.
    *   `has_many :vector_embeddings`: A project can have many vector embeddings. Deleting a project also deletes its embeddings.
*   **Functionality**:
    *   Manages project status (pending, active, paused, completed, archived).
    *   Kicks off the project by creating an initial orchestration task.
    *   Pauses and resumes the project and its active tasks.
    *   Stores and searches knowledge (vector embeddings) associated with the project.
    *   Calculates LLM call statistics for all tasks in the project.

### 3. `Task` (`task.rb`)

*   **Purpose**: Represents a specific task within a project.  Tasks are the fundamental unit of work for the AI agent.
*   **Attributes**:
    *   `title`: The title of the task (string).
    *   `description`: A description of the task (text).
    *   `state`: The current state of the task (string, using a state machine: "pending", "active", "paused", "waiting\_on\_human", "completed", "failed").
    *   `task_type`: The type of task (string, e.g., "research", "code", "analysis").
    *   `metadata`: JSONB column for storing task-specific data (e.g., dependencies, error messages).
*   **Associations**:
    *   `belongs_to :project`:  Each task belongs to a project.
    *   `belongs_to :parent`:  Tasks can have parent-child relationships, forming a task hierarchy.
    *   `has_many :subtasks`: Child tasks (`Task` objects).
    *   `has_many :agent_activities`: A task can have many agent activities associated with it. Deleting a task also deletes its activities.
*   **Functionality**:
    *   Manages task state transitions (pending, active, paused, completed, failed).
    *   Enqueues tasks for processing by agent.
    *   Tracks dependencies between tasks.
    *   Stores knowledge (vector embeddings) related to the task.
    *   Calculates LLM call statistics for the task.

### 4. `AgentActivity` (`agent_activity.rb`)

*   **Purpose**: Represents a specific activity performed by an agent while working on a task.  It tracks the progress and status of an agent's execution.
*   **Attributes**:
    *   `agent_type`: The type of agent performing the activity (string).
    *   `status`: The current status of the activity (string).
    *   `error_message`: Any error messages encountered during the activity (text).
*   **Associations**:
    *   `belongs_to :task`: Each agent activity belongs to a task.
    *   `has_many :llm_calls`:  An agent activity can make many LLM calls. Deleting an activity also deletes its calls.
    *   `has_many :events`: An agent activity generates multiple events. Deleting an activity also deletes its events.
    *   `has_ancestry`: Used for representing a tree structure of agent activies.

*   **Functionality**:
    *   Tracks the status of the agent activity (e.g., running, completed, failed).
    *   Records error messages if the activity fails.
    *   Publishes events when the agent activity changes state.
    *   Can be paused and resumed.

### 5. `HumanInputRequest` (`human_input_request.rb`)

*   **Purpose**: Represents a request for human input during an agent's activity. This allows the agent to interact with humans for guidance or information.
*   **Attributes**:
    *   `question`: The question or prompt presented to the human (text).
    *   `response`: The response provided by the human (text).
    *   `status`: The status of the request (string, e.g., "pending", "answered", "ignored").
    *   `required`: Boolean indicating if human input is required for the task to proceed (boolean).
*   **Associations**:
    *   `belongs_to :task`: Each human input request belongs to a task.
    *   `belongs_to :agent_activity`: Each human input request belongs to an agent activity (optional).
*   **Functionality**:
    *   Manages the lifecycle of human input requests.
    *   Handles answering and ignoring requests.
    *   Resumes the task if it was waiting for the human input.
    *   Escalates to human intervention if the request times out.

### 6. `HumanIntervention` (`human_intervention.rb`)

*   **Purpose**: Represents a request for human intervention in a critical situation. This allows a human to take control and resolve issues that the agent cannot handle automatically.
*   **Attributes**:
    *   `description`: A description of the intervention required (text).
    *   `urgency`: The urgency level of the intervention (string, e.g., "low", "normal", "high", "critical").
    *   `status`: The status of the intervention (string, e.g., "pending", "acknowledged", "resolved", "dismissed").
    *   `resolution`: The resolution provided by the human (text).
*   **Associations**:
    *   `belongs_to :agent_activity`: A human intervention belongs to an agent activity (optional)
    *   `has_one :task, through: :agent_activity`: access to associated task.

*   **Functionality**:
    *   Manages the lifecycle of human intervention requests.
    *   Allows for acknowledgment, resolution, and dismissal of interventions.
    *   Notifies administrators of critical interventions.
    *   Resumes tasks that were paused due to the intervention.

### 7. `LlmCall` (`llm_call.rb`)

*   **Purpose**: Represents a call made to a Large Language Model (LLM) by an agent.  It tracks the details of the LLM interaction, including the prompt, response, cost, and tokens used.
*   **Attributes**:
    *   `provider`: The provider of the LLM (string, e.g., "OpenAI").
    *   `model`: The name of the LLM model (string, e.g., "gpt-3.5-turbo").
    *   `prompt`: The prompt sent to the LLM (text).
    *   `response`: The response received from the LLM (text).
    *   `cost`: The cost of the LLM call (float).
    *   `prompt_tokens`: The number of tokens in the prompt (integer).
    *   `completion_tokens`: The number of tokens in the completion (integer).
    *   `request_payload`: stores data about the llm call
    *   `response_payload`: stores data about the llm call
*   **Associations**:
    *   `belongs_to :agent_activity`: Each LLM call belongs to an agent activity.
*   **Functionality**:
    *   Tracks the cost and usage of LLM calls.
    *   Provides statistics on LLM usage by model and provider.

### 8. `VectorEmbedding` (`vector_embedding.rb`)

*   **Purpose**: Represents a vector embedding of a piece of text.  Vector embeddings are used for semantic search and knowledge storage.
*   **Attributes**:
    *   `content`: The text that was embedded (text).
    *   `embedding`: The vector embedding of the text (array of floats).
    *   `content_type`: The type of content (string, e.g., "text", "code").
    *   `collection`: A collection identifier for organizing embeddings (string).
*   **Associations**:
    *   `belongs_to :task`: A vector embedding can belong to a task (optional).
    *   `belongs_to :project`: A vector embedding can belong to a project (optional).
*   **Functionality**:
    *   Stores and searches for similar embeddings using vector similarity search.
    *   Provides a method for generating embeddings from text.

### 9. `Event` (`event.rb`)

*   **Purpose**: Represents an event that occurred within the system. Events are used for auditing, debugging, and triggering actions.
*   **Attributes**:
    *   `event_type`: The type of event (string).
    *   `data`: A hash containing event-specific data (JSON).
    *   `processed_at`: Timestamp when the event was processed (datetime).
    *   `priority`:  An integer representing the priority of the event.
*   **Associations**:
    *   `belongs_to :agent_activity`: An event can belong to an agent activity (optional for system events).
*   **Functionality**:
    *   Records events with associated data.
    *   Publishes events to an event bus for processing.
    *   Provides scopes for querying events.
    *   Supports system events (not tied to a specific agent activity).
    *   Validates events against a schema.

## Concerns

Concerns are modules that provide shared functionality to multiple models.

### 1. `Contextable` (`concerns/contextable.rb`)

*   **Purpose**: Provides a standardized way to access the context of a model (task, project, and agent activity).
*   **Functionality**:
    *   Includes associations for `task`, `project`, and `agent_activity`.
    *   Provides a `context` method to return a hash of context attributes.
    *   Automatically propagates context from associations.
    *   Provides a `with_context` method to set context from another object or a hash.

### 2. `DashboardBroadcaster` (`concerns/dashboard_broadcaster.rb`)

*   **Purpose**:  **DEPRECATED** Intended to provide a way to broadcast updates to a dashboard. However, this functionality is now handled by the `EventBus` system, making this concern essentially a no-op.  It exists for backwards compatibility.

### 3. `SolidQueueManagement` (`concerns/solid_queue_management.rb`)

*   **Purpose**: Manages queue configuration and concurrency control using SolidQueue.
*   **Functionality**:
    *   Provides a `with_concurrency_control` method to limit per-queue agent concurrency.
    *   Provides a `configure_recurring` method to set up recurring jobs.
    *   Provides methods for querying and managing pending jobs.

### 4. `EventPublisher` (`concerns/event_publisher.rb`)

*   **Purpose**: Provides a standardized way to publish events with proper context.
*   **Functionality**:
    *   Includes the `Contextable` concern.
    *   Provides a `publish_event` method to publish events with automatic inclusion of context.

### 5. `TaskStatusHelper` (`concerns/task_status_helper.rb`)

*   **Purpose**:  Provides helper methods for managing task statuses and calculating statistics.
*   **Functionality**:
    *   Provides a `task_status_counts` method to get counts of tasks by status.
    *   Provides a `task_status_summary` method to get a summary of task status.
    *   Provides methods for checking if all tasks are completed, any tasks are active, or any tasks are waiting on human input.

### 6. `EventSubscriber` (`concerns/event_subscriber.rb`)

*   **Purpose**:  Adds event subscription capabilities to a class.
*   **Functionality**:
    *   Provides a `subscribe_to` method to subscribe to events with a callback.
    *   Allows for both class-level and instance-level event handling.

## Model Relationships Summary

The models are interconnected to represent a complex system of projects, tasks, agents, human interaction, knowledge management, and event tracking. The `Contextable` concern plays a crucial role in ensuring that all models have access to the relevant context, while the `EventPublisher` concern enables the system to react to changes and provide real-time updates. `SolidQueueManagement` handles asynchronous processing of tasks and activities.
