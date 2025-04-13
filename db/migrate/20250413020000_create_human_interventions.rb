class CreateHumanInterventions < ActiveRecord::Migration[7.1]
  def change
    create_table :human_interventions do |t|
      # Core fields
      t.text :description, null: false
      t.string :urgency, null: false, default: 'normal'
      t.string :status, null: false, default: 'pending'
      t.text :resolution

      # Association with agent activity
      t.references :agent_activity, null: true, foreign_key: true

      # Timestamps for various status changes
      t.datetime :acknowledged_at
      t.datetime :resolved_at
      t.datetime :dismissed_at

      # User tracking for changes
      t.string :acknowledged_by
      t.string :resolved_by
      t.string :dismissed_by

      # Standard timestamps
      t.timestamps
    end

    # Add indexes for common queries
    add_index :human_interventions, :status
    add_index :human_interventions, :urgency
    add_index :human_interventions, [ :status, :urgency ]
  end
end
