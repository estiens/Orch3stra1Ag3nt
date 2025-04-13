class AddNotesToTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :tasks, :notes, :text
  end
end
