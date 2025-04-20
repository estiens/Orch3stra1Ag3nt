class DropEventsTable < ActiveRecord::Migration[8.0]
  def change
    drop_table :events do |t|
      # Add column definitions from the original create_events migration
      # if you need to make the migration reversible.
      # Example:
      # t.string :event_type, null: false
      # t.references :agent_activity, foreign_key: true
      # t.jsonb :data, default: {}
      # t.datetime :processed_at
      # t.integer :processing_attempts, default: 0
      # t.string :last_processing_error
      # t.integer :priority, default: 0
      # t.references :task, foreign_key: true
      # t.references :project, foreign_key: true
      # t.timestamps
    end
  end
end
