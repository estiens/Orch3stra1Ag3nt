class Task < ApplicationRecord
  include DashboardBroadcaster

  validates :title, presence: true

  has_many :agent_activities, dependent: :destroy
  # Events are associated with agent_activities, not directly with tasks
  # has_many :events, dependent: :destroy

  # Project association
  belongs_to :project, optional: true

  # Parent-child relationship
  belongs_to :parent, class_name: "Task", optional: true
  has_many :subtasks, class_name: "Task", foreign_key: "parent_id", dependent: :destroy

  # Task types
  TASK_TYPES = %w[general research code analysis review search orchestration].freeze

  # Store metadata as JSON
  # serialize :metadata, JSON

  # Scopes
  scope :root_tasks, -> { where(parent_id: nil) }
  scope :by_type, ->(type) { where(task_type: type) }
  scope :research_tasks, -> { where(task_type: "research") }
  scope :recent, -> { order(created_at: :desc) }

  # State machine for Task
  # Requires 'aasm' gem. If not installed, add 'gem "aasm"' to your Gemfile and run bundle install.
  include AASM

  aasm column: "state" do
    state :pending, initial: true
    state :active
    state :paused
    state :waiting_on_human
    state :completed
    state :failed

    event :activate do
      transitions from: [ :pending, :paused ], to: :active
      after do
        # Publish event for dashboard updates
        if agent_activities.any?
          agent_activities.last.publish_event("task_activated", { task_id: id, task_title: title })
        else
          # Create a temporary agent activity if needed for the event
          temp_activity = agent_activities.create!(agent_type: "system", status: "completed")
          temp_activity.publish_event("task_activated", { task_id: id, task_title: title })
        end

        # Enqueue the task for processing if it was activated
        enqueue_for_processing
      end
    end

    event :pause do
      transitions from: :active, to: :paused
      after do
        # Publish event for dashboard updates
        if agent_activities.any?
          agent_activities.last.publish_event("task_paused", { task_id: id, task_title: title })
        else
          # Create a temporary agent activity if needed for the event
          temp_activity = agent_activities.create!(agent_type: "system", status: "completed")
          temp_activity.publish_event("task_paused", { task_id: id, task_title: title })
        end
      end
    end

    event :wait_on_human do
      transitions from: :active, to: :waiting_on_human
    end

    event :complete do
      transitions from: [ :active, :waiting_on_human, :paused ], to: :completed
      after do
        # Publish event for dashboard updates
        if agent_activities.any?
          agent_activities.last.publish_event("task_completed", { task_id: id, task_title: title })
        else
          # Create a temporary agent activity if needed for the event
          temp_activity = agent_activities.create!(agent_type: "system", status: "completed")
          temp_activity.publish_event("task_completed", { task_id: id, task_title: title })
        end
      end
    end

    event :fail do
      transitions from: [ :pending, :active, :waiting_on_human, :paused ], to: :failed
      after do
        # Publish event for dashboard updates
        if agent_activities.any?
          agent_activities.last.publish_event("task_failed", { task_id: id, task_title: title, error: metadata&.dig("error_message") })
        else
          # Create a temporary agent activity if needed for the event
          temp_activity = agent_activities.create!(agent_type: "system", status: "completed")
          temp_activity.publish_event("task_failed", { task_id: id, task_title: title, error: metadata&.dig("error_message") })
        end
      end
    end

    event :resume do
      transitions from: :paused, to: :active
      after do
        # Publish event for dashboard updates
        if agent_activities.any?
          agent_activities.last.publish_event("task_resumed", { task_id: id, task_title: title })
        else
          # Create a temporary agent activity if needed for the event
          temp_activity = agent_activities.create!(agent_type: "system", status: "completed")
          temp_activity.publish_event("task_resumed", { task_id: id, task_title: title })
        end

        # Enqueue the task for processing when resumed
        enqueue_for_processing
      end
    end
  end

  # Mark this task as failed with an optional error message
  def mark_failed(error_message = nil)
    # Use the AASM fail! event to change state
    fail! if may_fail?

    # Record error message in metadata if provided
    if error_message.present?
      self.metadata ||= {}
      self.metadata["error_message"] = error_message
      save
    end

    true
  end

  # Callbacks
  before_create :propagate_project_from_parent
  after_create :ensure_metadata_exists

  # Get the path of tasks from root to this task
  def task_path
    path = []
    current = self

    while current
      path.unshift(current)
      current = current.parent
    end

    path
  end

  # Check if this task has any pending human input requests
  def waiting_for_human_input?
    HumanInputRequest.where(task_id: id, status: "pending").exists?
  end

  # Default task type if not specified
  def task_type
    self[:task_type] || "general"
  end

  # Find the root task (topmost ancestor)
  def root_task
    parent_id.present? ? parent.root_task : self
  end

  # Search the project's knowledge base related to this task
  def search_knowledge(query, limit = 5)
    return [] unless project.present?

    project.search_knowledge(query, limit)
  end

  # Store knowledge in the project's semantic memory
  def store_knowledge(content, content_type: "text", collection: "default", metadata: {})
    return nil unless project.present?

    project.store_knowledge(
      content,
      content_type: content_type,
      collection: collection,
      metadata: metadata.merge(task_id: id, task_title: title)
    )
  end

  # Access events through agent_activities (helper method)
  def events
    Event.where(agent_activity_id: agent_activities.pluck(:id))
  end

  # Get LLM call statistics for this task
  def llm_call_stats
    activity_ids = agent_activities.pluck(:id)
    calls = LlmCall.where(agent_activity_id: activity_ids)

    {
      count: calls.count,
      total_cost: calls.sum(:cost).round(4),
      total_tokens: calls.sum(:prompt_tokens).to_i + calls.sum(:completion_tokens).to_i,
      models: calls.group(:model).count
    }
  end

  # Task dependencies methods
  def depends_on_task_ids
    metadata&.dig("depends_on_task_ids") || []
  end

  def depends_on_task_ids=(ids)
    self.metadata ||= {}
    self.metadata["depends_on_task_ids"] = Array(ids).map(&:to_i)
    save if persisted?
  end

  # Check if all dependencies are satisfied
  def dependencies_satisfied?
    return true if depends_on_task_ids.empty?

    completed_ids = Task.where(id: depends_on_task_ids, state: "completed").pluck(:id)
    depends_on_task_ids.all? { |id| completed_ids.include?(id) }
  end

  # Enqueue this task for processing based on its type
  # @param options [Hash] additional options for the agent
  # @return [AgentActivity] the created agent activity
  def enqueue_for_processing(options = {})
    return unless active?

    # Don't enqueue if the project is paused
    if project && project.status == "paused"
      Rails.logger.info "[Task #{id}] Not enqueueing because project #{project.id} is paused"
      return false
    end

    # Skip agent spawning in test environment to avoid side effects
    if Rails.env.test? && !options[:force_spawn]
      Rails.logger.info "[Task #{id}] Skipping agent spawning in test environment"
      return true
    end

    # Use the centralized agent spawning service
    AgentSpawningService.spawn_for_task(self, options)
  end

  private

  # Ensure a subtask belongs to the same project as its parent
  def propagate_project_from_parent
    if parent_id.present? && project_id.nil?
      self.project_id = parent.project_id
    end
  end

  # Ensure metadata exists
  def ensure_metadata_exists
    self.metadata ||= {}
    save if metadata_changed?
  end
end
