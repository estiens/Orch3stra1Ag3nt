class AddCompletedAtToAgentActivities < ActiveRecord::Migration[8.0]
  def change
    add_column :agent_activities, :completed_at, :datetime
  end
end
