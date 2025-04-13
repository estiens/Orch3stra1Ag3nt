# EventDispatchJob: Asynchronously dispatches events to registered handlers
class EventDispatchJob < ApplicationJob
  queue_as :events

  # Use a more aggressive retry strategy since event processing is critical
  retry_on StandardError, wait: :exponentially_longer, attempts: 5

  discard_on ActiveRecord::RecordNotFound do |job, error|
    Rails.logger.error("EventDispatchJob failed: Event ID #{job.arguments.first} not found")
  end

  # @param event_id [Integer] the ID of the event to dispatch
  def perform(event_id)
    event = Event.find(event_id)

    Rails.logger.info("Processing event #{event.event_type} [#{event_id}] via job")

    # Use the EventBus singleton to dispatch the event
    EventBus.instance.dispatch_event(event)

    # Update the event to show it's been processed
    event.update(processed_at: Time.current)
  rescue => e
    Rails.logger.error("Error processing event #{event_id}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    raise # Re-raise to trigger retry
  end
end
