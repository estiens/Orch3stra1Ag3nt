class CreateDashboardTaskEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :dashboard_task_events do |t|
      t.references :task, null: false, foreign_key: true
      t.string :event_type, null: false
      t.jsonb :metadata, default: {}

      t.timestamps
    end
    
    add_index :dashboard_task_events, :event_type
  end
end
