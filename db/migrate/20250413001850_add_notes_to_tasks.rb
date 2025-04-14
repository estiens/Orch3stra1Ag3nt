class AddNotesToTasks < ActiveRecord::Migration[8.0]
  def change
    # The notes column is already defined in the CreateTasks migration
    # add_column :tasks, :notes, :text
  end
end
