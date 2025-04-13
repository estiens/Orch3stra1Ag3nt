class AgentActivity < ApplicationRecord
  validates :agent_type, presence: true
  validates :status, presence: true

  belongs_to :task
  has_ancestry

  has_many :llm_calls, dependent: :destroy
  has_many :events, dependent: :destroy

  # Mark this activity as failed with an error message
  def mark_failed(error_message)
    update(
      status: "failed",
      error_message: error_message
    )
  end
end
