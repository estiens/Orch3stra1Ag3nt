class CreatePromptVersions < ActiveRecord::Migration[7.1]
  def change
    create_table :prompt_versions do |t|
      t.references :prompt, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.integer :version_number, null: false
      t.text :content, null: false
      t.string :commit_message
      t.jsonb :metadata, default: {}

      t.timestamps

      t.index [ :prompt_id, :version_number ], unique: true
    end
  end
end
