# frozen_string_literal: true

# PromptVersion: Represents a specific version of a prompt
# Allows tracking changes to prompts over time
class PromptVersion < ApplicationRecord
  # Associations
  belongs_to :prompt
  belongs_to :user, optional: true
  # Removed legacy associations as part of refactoring
  # has_many :prompt_evaluations, dependent: :nullify
  # has_many :prompt_usages, dependent: :nullify

  # Validations
  validates :content, presence: true
  validates :version_number, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :version_number, uniqueness: { scope: :prompt_id }

  # Scopes
  scope :ordered, -> { order(version_number: :desc) }

  # Get the diff between this version and another
  def diff_with(other_version)
    return nil unless other_version.is_a?(PromptVersion) && other_version.prompt_id == prompt_id

    # Simple diff implementation - could be replaced with a more sophisticated diff algorithm
    {
      from_version: other_version.version_number,
      to_version: version_number,
      changes: {
        added: content.split("\n") - other_version.content.split("\n"),
        removed: other_version.content.split("\n") - content.split("\n")
      }
    }
  end

  # Compare with previous version
  def diff_with_previous
    previous = prompt.prompt_versions.where("version_number < ?", version_number).ordered.first
    diff_with(previous) if previous
  end

  # Revert to this version
  def revert_to(user = nil, message = nil)
    prompt.create_version(
      content,
      message || "Reverted to version #{version_number}",
      user
    )
  end

  # Deprecated: Get performance metrics for this version - now handled via LlmCall association
  # def performance_metrics
  #   evaluations = prompt_evaluations.where(prompt_version_id: id)
  #   return {} if evaluations.empty?
  #
  #   {
  #     average_score: evaluations.average(:score).to_f.round(2),
  #     count: evaluations.count,
  #     success_rate: (evaluations.where("score >= ?", 0.7).count.to_f / evaluations.count * 100).round(2)
  #   }
  # end
end
