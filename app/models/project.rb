class Project < ApplicationRecord
  include TaskStatusHelper
  
  # Associations
  has_many :tasks, dependent: :destroy
  has_many :vector_embeddings, dependent: :destroy

  # Validations
  validates :name, presence: true

  # # Serialization
  # serialize :settings, JSON
  # serialize :metadata, JSON

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :completed, -> { where(status: "completed") }
  scope :by_priority, -> { order(priority: :desc) }
  scope :recent, -> { order(created_at: :desc) }

  # Status values
  STATUSES = %w[pending active paused completed archived].freeze
  validates :status, inclusion: { in: STATUSES }

  # Callback to set defaults
  after_initialize :set_defaults, if: :new_record?

  # Methods to get all root tasks (tasks without parents)
  def root_tasks
    tasks.where(parent_id: nil)
  end

  # Create initial orchestration task
  def kickoff!
    # Only kickoff if project is pending and has no tasks yet
    return false unless status == "pending" && tasks.empty?

    # Update status to active
    update!(status: "active")

    # Create the initial orchestration task
    orchestration_task = tasks.create!(
      title: "Project Orchestration: #{name}",
      description: "Initial task to plan and coordinate project: #{description}",
      task_type: "orchestration",
      priority: "high",
      metadata: {
        project_kickoff: true,
        project_settings: settings
      }
    )

    # Event will be published by the orchestration task when it's activated

    # Publish event to trigger OrchestratorAgent
    Event.publish(
      "project_created",
      {
        project_id: id,
        task_id: orchestration_task.id,
        priority: priority
      },
      priority: Event::HIGH_PRIORITY
    )

    # Activate the task to start processing
    orchestration_task.activate!

    # Return the orchestration task
    orchestration_task
  end

  # Get all task activities across the project
  def all_agent_activities
    task_ids = tasks.pluck(:id)
    AgentActivity.where(task_id: task_ids)
  end

  # Simple search across project's embeddings
  def search_knowledge(query, limit = 5)
    VectorEmbedding.search(
      text: query,
      limit: limit,
      project_id: id
    )
  end

  # Store knowledge in project's semantic memory
  def store_knowledge(content, content_type: "text", collection: "default", metadata: {})
    VectorEmbedding.store(
      content: content,
      content_type: content_type,
      collection: collection,
      project: self,
      metadata: metadata
    )
  end

  # Pause this project and all its active tasks
  def pause!
    return false if status == "paused"

    # Update project status
    update(status: "paused")

    # Pause all active tasks
    tasks.where(state: "active").each do |task|
      task.pause! if task.may_pause?
    end

    # Find a task to publish the event through, or create a temporary one
    publisher_task = tasks.first

    if publisher_task&.agent_activities&.any?
      # Use the last agent activity to publish the event
      publisher_task.agent_activities.last.publish_event(
        "project_paused",
        {
          project_id: id,
          project_name: name
        }
      )
    else
      # Create a system event if no agent activities exist
      Event.publish(
        "project_paused",
        {
          project_id: id,
          project_name: name
        },
        {}
      ) if defined?(Event)
    end

    true
  end

  # Resume this project
  def resume!
    return false unless status == "paused"

    # Update project status
    update(status: "active")

    # Find a task to publish the event through, or create a temporary one
    publisher_task = tasks.first

    if publisher_task&.agent_activities&.any?
      # Use the last agent activity to publish the event
      publisher_task.agent_activities.last.publish_event(
        "project_resumed",
        {
          project_id: id,
          project_name: name
        }
      )
    else
      # Create a system event if no agent activities exist
      Event.publish(
        "project_resumed",
        {
          project_id: id,
          project_name: name
        },
        {}
      ) if defined?(Event)
    end

    true
  end

  private

  def set_defaults
    self.status ||= "pending"
    self.settings ||= {
      "max_concurrent_tasks" => 5,
      "llm_budget_limit" => 10.0,  # In dollars
      "task_timeout_hours" => 24,
      "allow_web_search" => true,
      "allow_code_execution" => false
    }

    self.metadata ||= {}
  end
end
