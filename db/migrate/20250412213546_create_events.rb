class CreateEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :events do |t|
      t.references :agent_activity, null: false, foreign_key: true
      t.string :event_type
      t.text :data
      t.datetime :occurred_at

      t.timestamps
    end
  end
end
