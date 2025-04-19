# frozen_string_literal: true

# PromptEvaluation: Tracks evaluations of prompt performance
# Allows measuring and comparing prompt effectiveness
class PromptEvaluation < ApplicationRecord
  # Associations
  belongs_to :prompt
  belongs_to :prompt_version, optional: true
  belongs_to :evaluator, class_name: "User", optional: true
  belongs_to :agent_activity, optional: true

  # Validations
  validates :score, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validates :evaluation_type, presence: true

  # Callbacks
  before_validation :set_prompt_version, if: -> { prompt_version_id.nil? && prompt_id.present? }

  # Scopes
  scope :human_evaluations, -> { where(evaluation_type: "human") }
  scope :automated_evaluations, -> { where(evaluation_type: "automated") }
  scope :by_date_range, ->(start_date, end_date) { where(created_at: start_date..end_date) }

  # Constants
  EVALUATION_TYPES = %w[human automated].freeze

  # Calculate success based on threshold
  def successful?(threshold = 0.7)
    score >= threshold
  end

  # Add feedback comments
  def add_feedback(comment, user = nil)
    # Combine existing and new feedback
    existing_feedback = feedback || []
    new_feedback = {
      comment: comment,
      user_id: user&.id,
      timestamp: Time.current
    }

    update(feedback: existing_feedback + [ new_feedback ])
  end

  private

  # Set the prompt version to the current version of the prompt
  def set_prompt_version
    self.prompt_version = prompt.current_version if prompt
  end
end
