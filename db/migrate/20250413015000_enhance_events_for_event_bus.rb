class EnhanceEventsForEventBus < ActiveRecord::Migration[7.1]
  def change
    change_table :events do |t|
      # Make agent_activity_id optional for system-wide events
      change_column_null :events, :agent_activity_id, true

      # Add fields for event processing
      t.datetime :processed_at
      t.integer :processing_attempts, default: 0
      t.string :processing_error

      # Add a priority field for event ordering
      t.integer :priority, default: 0

      # Add an index on event_type for faster lookups
      t.index :event_type
    end
  end
end
