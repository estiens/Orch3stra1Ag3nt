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

    # Process the event, which will dispatch it via the event bus and mark it as processed
    event.process

    Rails.logger.info("Successfully processed event #{event.event_type} [#{event_id}]")
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error("Error processing event #{event_id}: Couldn't find Event with 'id'=#{event_id}")
    Rails.logger.error(e.backtrace.join("\n"))
    # Don't re-raise - this will be caught by the discard_on handler
  rescue => e
    Rails.logger.error("Error processing event #{event_id}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))

    # Record the attempt in the event
    if defined?(event) && event.present?
      event.record_processing_attempt!(e)
    end

    raise # Re-raise to trigger retry
  end
end
