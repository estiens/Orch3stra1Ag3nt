class AddDetailsToTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :tasks, :parent_id, :integer
    add_column :tasks, :task_type, :string, default: "general"
    add_column :tasks, :metadata, :json
    add_column :tasks, :priority, :string, default: "normal"
    add_column :tasks, :result, :text

    add_index :tasks, :parent_id
    add_index :tasks, :task_type
    add_index :tasks, :state
  end
end
