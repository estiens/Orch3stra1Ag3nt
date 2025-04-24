# frozen_string_literal: true

# Contextable: A concern to standardize context tracking across models
# Provides methods for accessing task, project, and agent_activity context
module Contextable
  extend ActiveSupport::Concern

  included do
    # Define associations if they don't exist
    if respond_to?(:belongs_to)
      belongs_to :task, optional: true unless method_defined?(:task)
      belongs_to :agent_activity, optional: true unless method_defined?(:agent_activity)

      # Define project association if it doesn't exist and task association exists
      belongs_to :project, optional: true unless method_defined?(:project)
    end

    # Define helper methods to access context in ActiveRecord models
    if ancestors.include?(ActiveRecord::Base)
      before_validation :propagate_context, if: :new_record?
    end
  end

  # Get the current context as a hash
  # @return [Hash] the current context
  def context
    {
      task_id: self.try(:task_id),
      project_id: self.try(:project_id),
      agent_activity_id: self.try(:agent_activity_id)
    }.compact
  end

  # Set context from another contextable object or hash
  # @param contextable [Object, Hash] object with context or hash with context keys
  # @return [self]
  def with_context(contextable)
    case contextable
    when Hash
      self.task_id = contextable[:task_id] if contextable[:task_id].present? && respond_to?(:task_id=)
      self.project_id = contextable[:project_id] if contextable[:project_id].present? && respond_to?(:project_id=)
      self.agent_activity_id = contextable[:agent_activity_id] if contextable[:agent_activity_id].present? && respond_to?(:agent_activity_id=)
    else
      # Try to get context from the object
      self.task_id = contextable.task_id if contextable.respond_to?(:task_id) && contextable.task_id.present? && respond_to?(:task_id=)
      self.project_id = contextable.project_id if contextable.respond_to?(:project_id) && contextable.project_id.present? && respond_to?(:project_id=)
      self.agent_activity_id = contextable.agent_activity_id if contextable.respond_to?(:agent_activity_id) && contextable.agent_activity_id.present? && respond_to?(:agent_activity_id=)
    end
    self
  end

  # Get the task from context
  # @return [Task, nil] the task or nil
  def task
    return @task if defined?(@task) && @task
    return nil unless respond_to?(:task_id) && task_id.present?
    @task = Task.find_by(id: task_id)
  end

  # Get the project from context
  # @return [Project, nil] the project or nil
  def project
    return @project if defined?(@project) && @project
    id = project_id if respond_to?(:project_id)
    id ||= task&.project&.id if respond_to?(:task)
    id ||= agent_activity&.task&.project&.id if respond_to?(:agent_activity)

    @project = Project.find_by(id: id)
  end

  # Get the agent_activity from context
  # @return [AgentActivity, nil] the agent_activity or nil
  def agent_activity
    return @agent_activity if defined?(@agent_activity) && @agent_activity
    return nil unless respond_to?(:agent_activity_id) && agent_activity_id.present?
    @agent_activity = AgentActivity.find_by(id: agent_activity_id)
  end

  private

  # Propagate context from associations
  def propagate_context
    # If we have a task but no project, get project from task
    if respond_to?(:project_id=) && respond_to?(:task) && task.present? && task.project_id.present? &&
       (self.try(:project_id).blank?)
      self.project_id = task.project_id
    end

    # If we have an agent_activity but no task, get task from agent_activity
    if respond_to?(:task_id=) && respond_to?(:agent_activity) && agent_activity.present? && agent_activity.task_id.present? &&
       (self.try(:task_id).blank?)
      self.task_id = agent_activity.task_id
    end
  end
end
