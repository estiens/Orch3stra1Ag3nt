# frozen_string_literal: true

# ProjectionManager: Service for managing event projections
# Handles projection registration, rebuilding, and access
class ProjectionManager
  class << self
    # Get all registered projections
    def projections
      @projections ||= {}
    end

    # Register a projection
    def register(name, projection_class)
      projections[name] = projection_class.create_handler
      Rails.logger.info("Registered projection: #{name}")
    end

    # Get a specific projection
    def get(name)
      projections[name]
    end

    # Rebuild a specific projection
    def rebuild(name)
      projection = projections[name]
      if projection
        projection.unsubscribe
        result = projection.rebuild
        projection.subscribe
        Rails.logger.info("Rebuilt projection: #{name}")
        result
      else
        Rails.logger.error("Projection not found: #{name}")
        nil
      end
    end

    # Rebuild all projections
    def rebuild_all
      projections.each_key do |name|
        rebuild(name)
      end
      Rails.logger.info("Rebuilt all projections")
    end

    # Initialize the projection manager with default projections
    def initialize_projections
      register(:event_counter, EventCounterProjection)
      # Register more projections here as they are created

      Rails.logger.info("Initialized projection manager with #{projections.size} projections")
    end
  end
end
