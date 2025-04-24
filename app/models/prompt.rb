# frozen_string_literal: true

# Prompt model: Represents a reusable, versionable prompt template
# Prompts can be used by agents and other components to generate consistent LLM inputs
class Prompt < ApplicationRecord
  # Associations
  belongs_to :creator, class_name: "User", optional: true
  has_many :llm_calls, dependent: :nullify

  # Validations
  validates :name, presence: true, uniqueness: true
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/ }
  validates :description, presence: true

  # Callbacks
  before_validation :generate_slug, if: -> { slug.blank? && name.present? }
  after_create :create_initial_version

  # Scopes
  scope :active, -> { where(active: true) }
  scope :by_category, ->(category_id) { where(prompt_category_id: category_id) }
  scope :search, ->(query) { where("name ILIKE ? OR description ILIKE ?", "%#{query}%", "%#{query}%") }

  # Get the current version number (stored as a field)
  def current_version
    version_number || 1
  end

  # Get the prompt template content (stored directly in the model)
  def content
    template_content
  end

  # Update the prompt content and increment version
  def update_content(content, message = nil, user = nil)
    next_version_number = (version_number || 0) + 1

    update!(
      template_content: content,
      version_number: next_version_number,
      version_message: message || "Updated prompt content",
      version_updated_by: user,
      version_updated_at: Time.current
    )
  end

  # Render the prompt with provided variables
  def render(variables = {})
    template = current_version&.content
    return nil unless template

    # Simple template rendering using regular expressions
    # For more complex needs, consider using a template engine like Liquid
    template.gsub(/\{\{([^}]+)\}\}/) do |match|
      var_name = Regexp.last_match(1).strip
      variables[var_name.to_sym] || variables[var_name] || match
    end
  end


  private

  def generate_slug
    self.slug = name.parameterize.underscore
  end

  def create_initial_version
    update(
      template_content: "# #{name}\n\n#{description}\n\n# Template content goes here",
      version_number: 1,
      version_message: "Initial version",
      version_updated_at: Time.current
    )
  end
end
