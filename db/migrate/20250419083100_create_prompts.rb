class CreatePrompts < ActiveRecord::Migration[7.1]
  def change
    create_table :prompts do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.boolean :active, default: true
      t.jsonb :metadata, default: {}

      t.timestamps

      t.index :slug, unique: true
    end
  end
end
