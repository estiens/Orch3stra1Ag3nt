class CreatePromptUsages < ActiveRecord::Migration[7.1]
  def change
    create_table :prompt_usages do |t|
      t.references :prompt, null: false, foreign_key: true
      t.references :prompt_version, foreign_key: true
      t.references :agent_activity, foreign_key: true
      t.string :agent_type, null: false
      t.boolean :successful
      t.integer :tokens_used
      t.jsonb :metadata, default: {}

      t.timestamps

      t.index :agent_type
      t.index :created_at
    end
  end
end
