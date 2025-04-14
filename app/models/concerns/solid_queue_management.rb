# Manages queue configuration and concurrency for SolidQueue
# To be included in agent classes
module SolidQueueManagement
  extend ActiveSupport::Concern

  included do
    # Limit per-queue agent concurrency using SolidQueue's semaphore
    def self.with_concurrency_control(&block)
      # Ensure queue_name and concurrency_limit are available here
      # Either pass them in, or ensure they are accessible class methods
      limit = respond_to?(:concurrency_limit) ? concurrency_limit : 5 # Default limit
      q_name = respond_to?(:queue_name) ? queue_name : name.demodulize.underscore.to_sym

      begin
        semaphore = SolidQueue::Semaphore.new(name: q_name, limit: limit, expires_in: 30.minutes)


        acquired = semaphore.acquire

        if acquired
          begin
            # Lock acquired, execute the original block content
            yield
          ensure
            # IMPORTANT: Release the lock after the block executes or if an error occurs
            semaphore.release
            Rails.logger.debug "[*SolidQueueManagement] Released semaphore lock for #{q_name}."
          end
        else
          # Failed to acquire the lock
          Rails.logger.warn "[*SolidQueueManagement] Failed to acquire semaphore lock for #{q_name}. Job not enqueued."
          # Prevent the job from being enqueued by returning nil or raising an error
          nil # Returning nil seems reasonable here.
        end
      rescue NameError => e
         # Handle cases where SolidQueue::Semaphore might not be defined yet or gem missing
         Rails.logger.warn "[*SolidQueueManagement] SolidQueue::Semaphore not available? Running without lock. Error: #{e.message}"
         yield # Fallback to running without lock
      rescue => e
         Rails.logger.error "[*SolidQueueManagement] Error during semaphore operation for #{q_name}: #{e.message}"
         # Decide whether to raise or fallback
         # Raising might be safer to prevent unexpected behavior
         raise # Re-raise other semaphore errors
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
