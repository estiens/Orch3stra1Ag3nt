class Project < ApplicationRecord
  # Associations
  has_many :tasks, dependent: :destroy
  has_many :vector_embeddings, dependent: :destroy

  # Validations
  validates :name, presence: true

  # Serialization
  serialize :settings, JSON
  serialize :metadata, JSON

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

  private

  def set_defaults
    self.settings ||= {
      max_concurrent_tasks: 5,
      llm_budget_limit: 10.0,  # In dollars
      task_timeout_hours: 24,
      allow_web_search: true,
      allow_code_execution: false
    }

    self.metadata ||= {}
  end
end
