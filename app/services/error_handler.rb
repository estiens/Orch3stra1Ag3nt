# ErrorHandler: Central error handling and recovery service
# Provides standardized error handling across agents, jobs, and tools
class ErrorHandler
  include Singleton

  # Class methods - delegates to instance
  class << self
    delegate :handle_error, :with_retries, :log_error, :report_error, to: :instance
  end

  # Standard error types
  TRANSIENT_ERRORS = [
    Timeout::Error,
    Net::ReadTimeout,
    Net::OpenTimeout,
    Errno::ECONNREFUSED,
    Errno::ECONNRESET,
    Faraday::ConnectionFailed,
    Faraday::TimeoutError
  ].freeze

  LLM_ERRORS = [
    # Define Regent and LLM specific errors here
  ].freeze

  # Initialize with default error reporters
  def initialize
    @error_reporters = []
    @mutex = Mutex.new
  end

  # Register an error reporter (like Sentry, Bugsnag, etc.)
  def register_reporter(reporter)
    @mutex.synchronize do
      @error_reporters << reporter
    end
  end

  # Handle an error with appropriate logging and reporting
  # @param error [Exception] The error to handle
  # @param context [Hash] Additional context about the error
  # @param options [Hash] Options for error handling
  def handle_error(error, context = {}, options = {})
    # Enhance context with additional information
    enhanced_context = {
      timestamp: Time.current,
      environment: Rails.env
    }.merge(context)

    # Log the error
    log_error(error, enhanced_context)

    # Report to external services if not in development/test
    report_error(error, enhanced_context) unless Rails.env.development? || Rails.env.test?

    # Emit an event for the error if an agent_activity is provided
    if context[:agent_activity_id].present?
      emit_error_event(error, context)
    end

    # Return the error and handling status
    {
      error: error,
      context: enhanced_context,
      handled: true
    }
  end

  # Execute a block with automatic retries for transient errors
  # @param max_attempts [Integer] Maximum number of retry attempts
  # @param retry_delay [Integer] Base delay between retries in seconds
  # @param exceptions [Array] Exceptions to retry on (defaults to TRANSIENT_ERRORS)
  def with_retries(max_attempts: 3, retry_delay: 1, exceptions: TRANSIENT_ERRORS)
    attempts = 0

    begin
      attempts += 1
      yield
    rescue *exceptions => e
      if attempts < max_attempts
        # Calculate exponential backoff with jitter
        delay = retry_delay * (2 ** (attempts - 1)) + rand(0.1..0.5)

        Rails.logger.warn("Retry #{attempts}/#{max_attempts} after error: #{e.message}. Waiting #{delay.round(2)}s")

        sleep delay
        retry
      else
        Rails.logger.error("Failed after #{max_attempts} attempts: #{e.message}")
        raise
      end
    end
  end

  # Log an error with standardized format
  # @param error [Exception] The error to log
  # @param context [Hash] Additional context about the error
  def log_error(error, context = {})
    error_type = error.class.name
    message = error.message
    backtrace = error.backtrace&.first(10) || []

    # Format the error message for logging
    error_log = [
      "[ERROR] #{error_type}: #{message}",
      "Context: #{context.inspect}",
      "Backtrace:",
      backtrace.map { |line| "  #{line}" }.join("\n")
    ].join("\n")

    Rails.logger.error(error_log)
  end

  # Report an error to registered error reporting services
  # @param error [Exception] The error to report
  # @param context [Hash] Additional context about the error
  def report_error(error, context = {})
    @error_reporters.each do |reporter|
      begin
        reporter.report(error, context)
      rescue => e
        Rails.logger.error("Failed to report error to #{reporter.class.name}: #{e.message}")
      end
    end
  end

  private

  # Emit an error event for monitoring and recovery
  def emit_error_event(error, context)
    agent_activity_id = context[:agent_activity_id]
    task_id = context[:task_id]

    event_data = {
      error_type: error.class.name,
      error_message: error.message,
      agent_activity_id: agent_activity_id,
      task_id: task_id,
      context: context,
      recoverable: context[:recoverable] || transient_error?(error)
    }

    # Create an event for this error
    EventService.publish(
      "agent.error_occurred",
      event_data
      # Removed legacy priority option
    )
  end

  # Determine if an error is likely transient (i.e., retryable)
  def transient_error?(error)
    TRANSIENT_ERRORS.any? { |error_class| error.is_a?(error_class) }
  end
end
