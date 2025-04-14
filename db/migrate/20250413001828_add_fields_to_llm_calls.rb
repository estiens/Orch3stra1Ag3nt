class AddFieldsToLlmCalls < ActiveRecord::Migration[8.0]
  def change
    # These columns are already defined in the CreateLlmCalls migration
    # add_column :llm_calls, :provider, :string, default: "openrouter"
    # add_column :llm_calls, :model, :string
    # add_column :llm_calls, :prompt, :text
    # add_column :llm_calls, :response, :text
    # add_column :llm_calls, :tokens_used, :integer, default: 0
    
    # Add any new columns here if needed
    
  end
end
