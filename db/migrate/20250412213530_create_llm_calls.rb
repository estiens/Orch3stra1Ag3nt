class CreateLlmCalls < ActiveRecord::Migration[8.0]
  def change
    create_table :llm_calls do |t|
      t.references :agent_activity, null: false, foreign_key: true
      t.text :request_payload
      t.text :response_payload
      t.float :duration
      t.decimal :cost

      t.timestamps
    end
  end
end
