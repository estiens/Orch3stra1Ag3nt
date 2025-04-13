class AddMetadataToAgentActivities < ActiveRecord::Migration[8.0]
  def change
    add_column :agent_activities, :metadata, :jsonb, null: false, default: {}
  end
end
