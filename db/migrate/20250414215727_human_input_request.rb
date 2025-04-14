class HumanInputRequest < ActiveRecord::Migration[8.0]
  def change
    create_table :human_input_requests do |t|
      t.references :task, null: false, foreign_key: true
      t.references :agent_activity, null: true, foreign_key: true # Optional association
      t.text :question, null: false
      t.boolean :required, default: false
      t.string :status, null: false, default: "pending"
      t.text :response
      t.datetime :responded_at
      t.string :answered_by # Optional: track who answered

      # Optional Expiry fields if you plan to use timeouts
      # t.datetime :expires_at
      # t.integer :timeout_minutes

      t.timestamps
    end

    # Add indexes for common lookups
    add_index :human_input_requests, :status
    add_index :human_input_requests, [:task_id, :status]
  end
end