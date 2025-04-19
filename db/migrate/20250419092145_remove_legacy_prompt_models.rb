class RemoveLegacyPromptModels < ActiveRecord::Migration[8.0]
  def change
    drop_table :prompt_usages
    drop_table :prompt_evaluations
  end
end
