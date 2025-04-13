class AddErrorMessageAndResultToAgentActivities < ActiveRecord::Migration[8.0]
  def change
    add_column :agent_activities, :error_message, :text
    add_column :agent_activities, :result, :text
  end
end
