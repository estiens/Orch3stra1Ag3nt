class CreatePromptEvaluations < ActiveRecord::Migration[7.1]
  def change
    create_table :prompt_evaluations do |t|
      t.references :prompt, null: false, foreign_key: true
      t.references :prompt_version, foreign_key: true
      t.references :evaluator, foreign_key: { to_table: :users }
      t.references :agent_activity, foreign_key: true
      t.decimal :score, precision: 3, scale: 2, null: false
      t.string :evaluation_type, null: false
      t.text :comments
      t.jsonb :feedback, default: []
      t.jsonb :metadata, default: {}

      t.timestamps

      t.index [ :prompt_id, :prompt_version_id, :evaluation_type ]
    end
  end
end
