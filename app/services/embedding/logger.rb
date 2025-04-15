# frozen_string_literal: true

module Embedding
  # Centralized logging for embedding services
  class Logger
    # Log levels
    LEVELS = {
      debug: 0,
      info: 1,
      warn: 2,
      error: 3,
      fatal: 4
    }.freeze

    # Initialize with component name and optional minimum log level
    def initialize(component_name, min_level: :debug)
      @component_name = component_name
      @min_level = min_level
    end

    # Log methods for each level
    def debug(message)
      log(:debug, message)
    end

    def info(message)
      log(:info, message)
    end

    def warn(message)
      log(:warn, message)
    end

    def error(message)
      log(:error, message)
    end

    def fatal(message)
      log(:fatal, message)
    end

    # Timing helper for performance logging
    def time(action, level: :debug)
      start_time = Time.now
      yield if block_given?
      duration = Time.now - start_time
      log(level, "#{action} completed in #{duration.round(2)}s")
      duration
    end

    private

    # Central logging method
    def log(level, message)
      return unless should_log?(level)

      # Format the log message with component name
      formatted_message = "[Embedding::#{@component_name}] #{message}"

      # Use Rails logger with appropriate level
      case level
      when :debug
        Rails.logger.debug(formatted_message)
      when :info
        Rails.logger.info(formatted_message)
      when :warn
        Rails.logger.warn(formatted_message)
      when :error
        Rails.logger.error(formatted_message)
      when :fatal
        Rails.logger.fatal(formatted_message)
      end
    end

    # Check if we should log at this level
    def should_log?(level)
      LEVELS[level] >= LEVELS[@min_level]
    end
  end
end
