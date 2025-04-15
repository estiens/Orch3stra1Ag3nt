# frozen_string_literal: true

# TaskStatusHelper: A concern to help with task status management and statistics
# Provides methods for tracking task counts by status
module TaskStatusHelper
  extend ActiveSupport::Concern

  # Get counts of tasks by status
  # @return [Hash] counts of tasks by status
  def task_status_counts
    counts = {
      total_tasks: tasks.count,
      pending_tasks: tasks.where(state: "pending").count,
      active_tasks: tasks.where(state: "active").count,
      paused_tasks: tasks.where(state: "paused").count,
      completed_tasks: tasks.where(state: "completed").count,
      failed_tasks: tasks.where(state: "failed").count,
      waiting_on_human_tasks: tasks.where(state: "waiting_on_human").count
    }

    # Add percentage calculations if there are any tasks
    if counts[:total_tasks] > 0
      counts[:completion_percentage] = (counts[:completed_tasks].to_f / counts[:total_tasks] * 100).round
    else
      counts[:completion_percentage] = 0
    end

    counts
  end

  # Get a summary of task status for display
  # @return [String] summary of task status
  def task_status_summary
    counts = task_status_counts

    if counts[:total_tasks] == 0
      "No tasks"
    elsif counts[:completed_tasks] == counts[:total_tasks]
      "All tasks completed"
    else
      "#{counts[:completion_percentage]}% complete (#{counts[:completed_tasks]}/#{counts[:total_tasks]} tasks)"
    end
  end

  # Check if all tasks are completed
  # @return [Boolean] true if all tasks are completed
  def all_tasks_completed?
    return true if tasks.empty?
    tasks.where.not(state: "completed").count == 0
  end

  # Check if any tasks are active
  # @return [Boolean] true if any tasks are active
  def any_tasks_active?
    tasks.where(state: "active").exists?
  end

  # Check if any tasks are waiting on human input
  # @return [Boolean] true if any tasks are waiting on human input
  def any_tasks_waiting_on_human?
    tasks.where(state: "waiting_on_human").exists?
  end

  # Check if project is stalled (no activity in the last 24 hours)
  # @return [Boolean] true if project is stalled
  def stalled?
    return false if tasks.empty?

    # Check if any tasks were updated recently
    last_updated = tasks.maximum(:updated_at)
    return false if last_updated.nil?

    # Consider stalled if no updates in 24 hours
    last_updated < 24.hours.ago
  end

  # Get tasks that are blocking other tasks
  # @return [Array<Task>] array of blocking tasks
  def blocking_tasks
    # Find tasks that are dependencies for other tasks but not completed
    dependency_ids = tasks.map do |task|
      task.metadata&.dig("depends_on_task_ids")
    end.flatten.compact.uniq

    # Return tasks that are in the dependency list and not completed
    tasks.where(id: dependency_ids).where.not(state: "completed")
  end

  # Get tasks that can be started (all dependencies satisfied)
  # @return [Array<Task>] array of tasks that can be started
  def ready_to_start_tasks
    tasks.where(state: "pending").select(&:dependencies_satisfied?)
  end

  # Calculate estimated completion time based on task velocity
  # @return [Time, nil] estimated completion time or nil if can't be calculated
  def estimated_completion_time
    counts = task_status_counts
    return nil if counts[:total_tasks] == 0 || counts[:completed_tasks] == 0

    # Get the average time to complete tasks
    completed_tasks = tasks.where(state: "completed")
    return nil if completed_tasks.empty?

    # Calculate average completion time in hours for completed tasks
    avg_completion_hours = completed_tasks.map do |task|
      if task.completed_at && task.created_at
        (task.completed_at - task.created_at) / 3600.0
      else
        nil
      end
    end.compact.sum / completed_tasks.count

    return nil if avg_completion_hours.zero?

    # Calculate remaining work
    remaining_tasks = counts[:total_tasks] - counts[:completed_tasks]

    # Estimate completion time based on remaining tasks and average completion time
    remaining_hours = remaining_tasks * avg_completion_hours

    # Return estimated completion time
    Time.current + remaining_hours.hours
  end
end
