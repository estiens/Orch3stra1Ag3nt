class Task < ApplicationRecord
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
  TASK_TYPES = %w[general research code analysis review orchestration].freeze

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
      transitions from: [:pending, :paused], to: :active
    end
    
    event :pause do
      transitions from: :active, to: :paused
    end

    event :wait_on_human do
      transitions from: :active, to: :waiting_on_human
    end

    event :complete do
      transitions from: [:active, :waiting_on_human, :paused], to: :completed
    end

    event :fail do
      transitions from: [:pending, :active, :waiting_on_human, :paused], to: :failed
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
    
    completed_ids = Task.where(id: depends_on_task_ids, state: 'completed').pluck(:id)
    depends_on_task_ids.all? { |id| completed_ids.include?(id) }
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
