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
end
