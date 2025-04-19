class CreatePromptCategories < ActiveRecord::Migration[7.1]
  def change
    create_table :prompt_categories do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.jsonb :metadata, default: {}

      t.timestamps

      t.index :slug, unique: true
    end
  end
end
