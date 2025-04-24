# frozen_string_literal: true

# Migration to consolidate HumanIntervention and HumanInputRequest into HumanInteraction
class ConsolidateHumanInteractions < ActiveRecord::Migration[7.1]
  # Define local models for data update
  class MigrationHumanInteraction < ApplicationRecord
    self.table_name = :human_interactions
    belongs_to :agent_activity, class_name: 'ConsolidateHumanInteractions::MigrationAgentActivity', optional: true
  end

  class MigrationAgentActivity < ApplicationRecord
    self.table_name = :agent_activities
    belongs_to :task, class_name: 'ConsolidateHumanInteractions::MigrationTask', optional: true
  end

  class MigrationTask < ApplicationRecord
    self.table_name = :tasks
  end

  def up
    # --- Pre-checks ---
    interventions_exist = table_exists?(:human_interventions)
    input_requests_exist = table_exists?(:human_input_requests)

    unless interventions_exist
      puts "human_interventions table does not exist. Skipping rename and data update."
      # If input requests exist, still drop it later
    else
      # --- Schema Changes for human_interventions table ---
      puts "Renaming human_interventions to human_interactions..."
      rename_table :human_interventions, :human_interactions

      # Add interaction_type (non-nullable after update)
      add_column :human_interactions, :interaction_type, :string
      puts "Updating existing records to interaction_type='intervention'..."
      MigrationHumanInteraction.unscoped.update_all(interaction_type: 'intervention')
      change_column_null :human_interactions, :interaction_type, false

      # Add task_id (nullable initially for update)
      add_column :human_interactions, :task_id, :bigint
      add_foreign_key :human_interactions, :tasks, if_exists: true

      # Attempt to populate task_id for existing interventions from agent_activity
      puts "Populating task_id for existing interventions..."
      MigrationHumanInteraction.unscoped.includes(agent_activity: :task).find_each do |interaction|
        interaction.update_column(:task_id, interaction.agent_activity&.task&.id) if interaction.agent_activity&.task
      end
      # Note: task_id remains nullable as not all interactions might have one

      # Add other columns from HumanInputRequest
      add_column :human_interactions, :question, :text
      add_column :human_interactions, :response, :text
      add_column :human_interactions, :required, :boolean, default: false, null: false
      add_column :human_interactions, :expires_at, :datetime
      add_column :human_interactions, :responded_at, :datetime
      add_column :human_interactions, :answered_by, :string

      # Make original intervention columns nullable
      change_column_null :human_interactions, :urgency, true
      change_column_null :human_interactions, :description, true
      change_column_null :human_interactions, :resolution, true

      # Add indexes
      add_index :human_interactions, :interaction_type unless index_exists?(:human_interactions, :interaction_type)
      add_index :human_interactions, [ :task_id, :status ] unless index_exists?(:human_interactions, [ :task_id, :status ]) # Index now valid
      add_index :human_interactions, :status unless index_exists?(:human_interactions, :status)
      add_index :human_interactions, :expires_at unless index_exists?(:human_interactions, :expires_at)
      add_index :human_interactions, :task_id unless index_exists?(:human_interactions, :task_id) # Add index for task_id alone
    end

    # --- Drop Old Table ---
    if input_requests_exist
      puts "Dropping human_input_requests table..."
      drop_table :human_input_requests
    else
      puts "human_input_requests table does not exist. Skipping drop."
    end
  end

  def down
    # Recreate human_input_requests table (approximating schema)
    create_table :human_input_requests do |t|
      t.references :task, null: false, foreign_key: true
      t.references :agent_activity, foreign_key: true
      t.text :question, null: false
      t.boolean :required, default: false
      t.string :status, default: "pending", null: false
      t.text :response
      t.datetime :responded_at
      t.string :answered_by
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.datetime :expires_at
      t.index :status
      t.index [ :task_id, :status ]
    end

    # Revert human_interactions back to human_interventions
    if table_exists?(:human_interactions)
      # Cannot easily move data back, so we drop columns and rename
      remove_index :human_interactions, :interaction_type if index_exists?(:human_interactions, :interaction_type)
      remove_index :human_interactions, [ :task_id, :status ] if index_exists?(:human_interactions, [ :task_id, :status ])
      remove_index :human_interactions, :status if index_exists?(:human_interactions, :status)
      remove_index :human_interactions, :expires_at if index_exists?(:human_interactions, :expires_at)
      remove_index :human_interactions, :task_id if index_exists?(:human_interactions, :task_id)

      remove_foreign_key :human_interactions, :tasks if foreign_key_exists?(:human_interactions, :tasks)
      remove_column :human_interactions, :task_id
      remove_column :human_interactions, :interaction_type
      remove_column :human_interactions, :question
      remove_column :human_interactions, :response
      remove_column :human_interactions, :required
      remove_column :human_interactions, :expires_at
      remove_column :human_interactions, :responded_at
      remove_column :human_interactions, :answered_by

      # Restore null constraints (assuming original state)
      change_column_null :human_interactions, :urgency, false, 'normal'
      change_column_null :human_interactions, :description, false
      change_column_null :human_interactions, :resolution, true # Assuming resolution was nullable

      rename_table :human_interactions, :human_interventions
    else
      puts "human_interactions table does not exist. Cannot revert."
    end
  end
end
