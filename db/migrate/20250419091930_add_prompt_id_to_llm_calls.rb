class AddPromptIdToLlmCalls < ActiveRecord::Migration[8.0]
  def change
    add_column :llm_calls, :prompt_id, :integer
    add_foreign_key :llm_calls, :prompts
  end
end
