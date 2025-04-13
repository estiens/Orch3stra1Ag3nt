# Manages queue configuration and concurrency for SolidQueue
# To be included in agent classes
module SolidQueueManagement
  extend ActiveSupport::Concern

  included do
    # Limit per-queue agent concurrency using SolidQueue's semaphore
    def self.with_concurrency_control(key = nil)
      semaphore_key = key || "#{queue_name}_concurrency"
      concurrency_limit = self.concurrency_limit

      # Attempt to acquire the semaphore
      SolidQueue::Semaphore.new(
        semaphore_key,
        concurrency_limit,
        expires_at: 30.minutes.from_now
      ).acquire do
        # Will only execute if successfully acquired the semaphore
        yield
      end
    end

    # Configure a recurring job for this agent type
    # Example: OrchestratorAgent.configure_recurring(key: "hourly_orchestration",
    #                                              schedule: "every hour",
    #                                              prompt: "Check tasks")
    def self.configure_recurring(key:, schedule:, prompt:, options: {})
      SolidQueue::RecurringTask.create_or_update(
        key: key,
        schedule: schedule,
        class_name: "Agents::AgentJob",
        queue_name: queue_name.to_s,
        arguments: [ self.name, prompt, options ]
      )
    end

    # Find all agent jobs by type (both pending and running)
    def self.pending_jobs
      SolidQueue::Job.where(class_name: "Agents::AgentJob",
                           queue_name: queue_name.to_s,
                           finished_at: nil)
    end

    # Number of currently executing jobs for this agent type
    def self.running_count
      pending_jobs.joins(:claimed_execution).count
    end

    # Number of jobs waiting to be executed
    def self.queued_count
      pending_jobs.joins(:ready_execution).count
    end

    # Cancel all pending jobs for this agent type (useful for emergency stops)
    def self.cancel_all_pending
      pending_jobs.joins(:ready_execution).destroy_all
    end
  end
end
