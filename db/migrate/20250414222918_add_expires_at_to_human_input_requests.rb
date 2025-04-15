class AddExpiresAtToHumanInputRequests < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:human_input_requests, :expires_at)
      add_column :human_input_requests, :expires_at, :datetime
    end
  end
end
