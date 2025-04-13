class CreateProjects < ActiveRecord::Migration[8.0]
  def change
    create_table :projects do |t|
      t.string :name, null: false
      t.text :description
      t.string :status, default: 'pending'
      t.integer :priority, default: 5 # 1-10 scale
      t.jsonb :settings, null: false, default: {} # For resource limits, permissions, etc.
      t.jsonb :metadata, null: false, default: {} # For flexible attributes
      t.datetime :due_date
      t.datetime :completed_at

      t.timestamps
    end

    add_index :projects, :name
    add_index :projects, :status
    add_index :projects, :priority

    # Add project_id to tasks
    add_reference :tasks, :project, foreign_key: true, index: true

    # Update vector_embeddings to refer to projects
    add_reference :vector_embeddings, :project, foreign_key: true, index: true
  end
end
