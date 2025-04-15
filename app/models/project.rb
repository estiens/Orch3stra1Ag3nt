class Project < ApplicationRecord
  include TaskStatusHelper

  # Associations
  has_many :tasks, dependent: :destroy
  has_many :vector_embeddings, dependent: :destroy

  # Validations
  validates :name, presence: true
# Serialization for settings and metadata
serialize :settings, coder: JSON
serialize :metadata, coder: JSON
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

  # Create initial orchestration task with improved error handling
  def kickoff!
    # Only kickoff if project is pending and has no tasks yet
    return false unless status == "pending" && tasks.empty?

    begin
      # Use transaction to ensure all operations succeed or fail together
      ActiveRecord::Base.transaction do
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
            project_settings: settings,
            kickoff_time: Time.current
          }
        )

        # Publish event to trigger OrchestratorAgent with system_event flag
        begin
          # Find or create a dummy agent activity for the event
          dummy_activity = orchestration_task.agent_activities.first_or_create!(
            agent_type: "SystemEventPublisher",
            status: "completed"
          )

          # Publish through the dummy activity
          dummy_activity.publish_event(
            "project_created",
            {
              project_id: id,
              task_id: orchestration_task.id,
              priority: priority
            },
            { priority: Event::HIGH_PRIORITY }
          )
        rescue => e
          # Log but continue if event publishing fails
          Rails.logger.error("Failed to publish project_created event: #{e.message}")
        end

        # Activate the task to start processing
        orchestration_task.activate!

        # Return the orchestration task
        orchestration_task
      end
    rescue => e
      # Log the error
      Rails.logger.error("Project kickoff failed: #{e.message}")

      # Revert status if needed
      update(status: "pending") if status == "active"

      # Re-raise the error
      raise
    end
  end

  # Get all task activities across the project
  def all_agent_activities
    task_ids = tasks.pluck(:id)
    AgentActivity.where(task_id: task_ids)
  end
  
  # Get LLM call statistics for all tasks in this project
  def llm_call_stats
    activity_ids = all_agent_activities.pluck(:id)
    calls = LlmCall.where(agent_activity_id: activity_ids)
    
    {
      count: calls.count,
      total_cost: calls.sum(:cost).round(4),
      total_tokens: calls.sum(:total_tokens),
      models: calls.group(:model).count,
      providers: calls.group(:provider).count
    }
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

  # Pause this project and all its active tasks with improved error handling
  def pause!
    return false if status == "paused"

    begin
      # Update project status
      update(status: "paused")

      # Store pause time in metadata
      self.metadata ||= {}
      self.metadata["paused_at"] = Time.current
      save

      # Pause all active tasks
      pause_errors = []
      tasks.where(state: "active").each do |task|
        begin
          task.pause! if task.may_pause?
        rescue => e
          pause_errors << "Task #{task.id} (#{task.title}): #{e.message}"
        end
      end

      # Log any errors from pausing tasks
      if pause_errors.any?
        Rails.logger.warn("Some tasks failed to pause: #{pause_errors.join('; ')}")
      end

      # Publish event about project being paused
      begin
        # Find a task to publish the event through, or create a temporary one
        publisher_task = tasks.first

        if publisher_task&.agent_activities&.any?
          # Use the last agent activity to publish the event
          publisher_task.agent_activities.last.publish_event(
            "project_paused",
            {
              project_id: id,
              project_name: name,
              paused_at: Time.current,
              active_tasks_count: tasks.where(state: "active").count
            }
          )
        else
          # Create a system event if no agent activities exist
          Event.publish(
            "project_paused",
            {
              project_id: id,
              project_name: name,
              paused_at: Time.current
            },
            { system_event: true }
          ) if defined?(Event)
        end
      rescue => e
        # Log but don't fail if event publishing fails
        Rails.logger.error("Failed to publish project_paused event: #{e.message}")
      end

      true
    rescue => e
      Rails.logger.error("Failed to pause project: #{e.message}")
      false
    end
  end

  # Resume this project with improved error handling
  def resume!
    return false unless status == "paused"

    begin
      # Update project status
      update(status: "active")

      # Store resume time in metadata
      self.metadata ||= {}
      self.metadata["resumed_at"] = Time.current
      self.metadata["pause_duration"] = (Time.current - Time.parse(metadata["paused_at"].to_s)).to_i rescue nil
      save

      # Resume paused tasks that were active before
      resume_errors = []
      tasks.where(state: "paused").each do |task|
        begin
          # Only resume tasks that should be resumed automatically
          # Could add logic here to determine which tasks to resume
          task.resume! if task.may_resume?
        rescue => e
          resume_errors << "Task #{task.id} (#{task.title}): #{e.message}"
        end
      end

      # Log any errors from resuming tasks
      if resume_errors.any?
        Rails.logger.warn("Some tasks failed to resume: #{resume_errors.join('; ')}")
      end

      # Publish event about project being resumed
      begin
        # Find a task to publish the event through, or create a temporary one
        publisher_task = tasks.first

        if publisher_task&.agent_activities&.any?
          # Use the last agent activity to publish the event
          publisher_task.agent_activities.last.publish_event(
            "project_resumed",
            {
              project_id: id,
              project_name: name,
              resumed_at: Time.current,
              pause_duration: metadata["pause_duration"]
            }
          )
        else
          # Create a system event if no agent activities exist
          Event.publish(
            "project_resumed",
            {
              project_id: id,
              project_name: name,
              resumed_at: Time.current
            },
            { system_event: true }
          ) if defined?(Event)
        end
      rescue => e
        # Log but don't fail if event publishing fails
        Rails.logger.error("Failed to publish project_resumed event: #{e.message}")
      end

      true
    rescue => e
      Rails.logger.error("Failed to resume project: #{e.message}")
      false
    end
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
