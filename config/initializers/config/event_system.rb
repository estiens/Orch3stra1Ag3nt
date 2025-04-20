# frozen_string_literal: true

# Event System Configuration
# This file contains configuration settings for the event system

# Configuration flag indicating whether legacy Event records are created.
# This should be false now that the migration to RailsEventStore is complete.
Rails.configuration.create_event_records = false
