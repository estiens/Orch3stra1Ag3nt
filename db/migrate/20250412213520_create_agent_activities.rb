class CreateAgentActivities < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_activities do |t|
      t.references :task, null: false, foreign_key: true
      t.integer :parent_id
      t.string :agent_type
      t.string :status

      t.timestamps
    end
  end
end
