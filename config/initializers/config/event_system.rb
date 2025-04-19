# frozen_string_literal: true

# Event System Configuration
# This file contains configuration settings for the event system

# By default, create legacy Event records for backward compatibility
# Set this to false when fully migrated to RailsEventStore
Rails.configuration.create_event_records = true