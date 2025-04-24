# frozen_string_literal: true

# PromptCategory: Organizes prompts into logical categories
# Examples: "Analysis", "Research", "Coordination", "Code Generation"
class PromptCategory < ApplicationRecord
  # Associations
  has_many :prompts, dependent: :nullify

  # Validations
  validates :name, presence: true, uniqueness: true
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/ }
  validates :description, presence: true

  # Callbacks
  before_validation :generate_slug, if: -> { slug.blank? && name.present? }

  # Scopes
  scope :ordered, -> { order(:name) }
  scope :with_prompt_count, -> { left_joins(:prompts).select("prompt_categories.*, COUNT(prompts.id) as prompt_count").group("prompt_categories.id") }

  def prompt_count
    prompts.count
  end

  private

  def generate_slug
    self.slug = name.parameterize.underscore
  end
end
