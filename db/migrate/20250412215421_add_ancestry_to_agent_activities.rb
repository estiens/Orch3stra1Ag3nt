class AddAncestryToAgentActivities < ActiveRecord::Migration[8.0]
  def change
    add_column :agent_activities, :ancestry, :string
    add_index :agent_activities, :ancestry
  end
end
