# frozen_string_literal: true

module Embedding
  # Test class to demonstrate the logging functionality
  class TestLogging
    def self.run_test
      # Create a logger
      logger = Embedding::Logger.new("TestLogging")

      # Log at different levels
      logger.debug("This is a debug message")
      logger.info("This is an info message")
      logger.warn("This is a warning message")
      logger.error("This is an error message")

      # Test timing functionality
      duration = logger.time("Test operation", level: :info) do
        # Simulate some work
        sleep(0.5)
        # Return a value from the block
        "Operation result"
      end

      logger.info("Operation took #{duration.round(2)}s")

      # Test with different components
      api_logger = Embedding::Logger.new("ApiClient")
      api_logger.info("API client initialized")

      chunker_logger = Embedding::Logger.new("TextChunker")
      chunker_logger.info("Text chunker initialized")

      # Test with minimum log level
      quiet_logger = Embedding::Logger.new("QuietComponent", min_level: :warn)
      quiet_logger.debug("This debug message should not appear")
      quiet_logger.info("This info message should not appear")
      quiet_logger.warn("This warning message should appear")
      quiet_logger.error("This error message should appear")

      logger.info("Logging test completed")
    end
  end
end
