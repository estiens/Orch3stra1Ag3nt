class AddContextToEvents < ActiveRecord::Migration[8.0]
  def change
    add_reference :events, :task, null: true, foreign_key: true
    add_reference :events, :project, null: true, foreign_key: true

    # Add indexes for performance
    add_index :events, [ :event_type, :task_id ]
    add_index :events, [ :event_type, :project_id ]

    # Backfill task_id and project_id from agent_activity
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE events e
          SET task_id = a.task_id
          FROM agent_activities a
          WHERE e.agent_activity_id = a.id
          AND e.task_id IS NULL
        SQL

        execute <<-SQL
          UPDATE events e
          SET project_id = t.project_id
          FROM tasks t
          WHERE e.task_id = t.id
          AND e.project_id IS NULL
        SQL
      end
    end
  end
end
