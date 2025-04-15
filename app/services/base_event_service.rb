# frozen_string_literal: true

# BaseEventService provides common functionality for event handling services
# This centralizes logging, reporting, and other shared event handling logic
class BaseEventService
  attr_reader :logger

  def initialize
    @logger = Rails.logger
  end

  # Log an event being processed
  # @param event [Event] the event being processed
  # @param handler [String] the name of the handler processing the event
  def log_event_processing(event, handler)
    logger.info("#{handler} processing event: #{event.event_type} [#{event.id}]")
  end

  # Log successful event handling
  # @param event [Event] the event that was processed
  # @param handler [String] the name of the handler that processed the event
  # @param result [Object] optional result of the processing
  def log_event_success(event, handler, result = nil)
    logger.info("#{handler} successfully processed event: #{event.event_type} [#{event.id}]")
    
    if result
      if result.is_a?(String) && result.length > 100
        logger.debug("#{handler} result: #{result[0..100]}...")
      else
        logger.debug("#{handler} result: #{result.inspect}")
      end
    end
  end

  # Log failed event handling
  # @param event [Event] the event that failed processing
  # @param handler [String] the name of the handler that was processing the event
  # @param error [Exception] the error that occurred
  def log_event_failure(event, handler, error)
    logger.error("#{handler} failed to process event: #{event.event_type} [#{event.id}]")
    logger.error("Error: #{error.message}")
    logger.error(error.backtrace.join("\n")) if error.backtrace
  end

  # Record metrics for event processing
  # @param event [Event] the event being processed
  # @param start_time [Time] when processing started
  # @param success [Boolean] whether processing was successful
  def record_event_metrics(event, start_time, success)
    duration = Time.current - start_time
    
    # Log processing time
    logger.info("Event #{event.id} processed in #{duration.round(2)}s (success: #{success})")
    
    # Here you could add more sophisticated metrics collection
    # For example, sending to a monitoring service or storing in the database
  end

  # Process an event with proper logging and error handling
  # @param event [Event] the event to process
  # @param handler [String] the name of the handler processing the event
  # @yield Block that processes the event
  # @return [Object] the result of the block
  def process_event(event, handler)
    log_event_processing(event, handler)
    start_time = Time.current
    success = false
    
    begin
      # Execute the provided block
      result = yield
      success = true
      log_event_success(event, handler, result)
      result
    rescue => e
      log_event_failure(event, handler, e)
      # Re-raise the error to be handled by the caller
      raise
    ensure
      record_event_metrics(event, start_time, success)
    end
  end

  # Validate event data against expected fields
  # @param event [Event] the event to validate
  # @param required_fields [Array<String>] fields that must be present
  # @return [Boolean] true if valid, raises error if invalid
  def validate_event_data(event, required_fields)
    data = event.data
    
    missing_fields = required_fields.select do |field|
      data[field.to_s].nil? && data[field.to_sym].nil?
    end
    
    if missing_fields.any?
      error_msg = "Event #{event.id} missing required fields: #{missing_fields.join(', ')}"
      logger.error(error_msg)
      raise ArgumentError, error_msg
    end
    
    true
  end
end
