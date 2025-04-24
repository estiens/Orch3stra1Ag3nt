# frozen_string_literal: true

# PromptService: Service for fetching, rendering, and tracking prompts
# Provides a unified interface for agents to work with prompts
class PromptService
  # Initialize with optional agent and activity context
  def initialize(agent_type = nil, agent_activity = nil)
    @agent_type = agent_type
    @agent_activity = agent_activity
  end

  # Find a prompt by slug
  def find_prompt(slug)
    Prompt.find_by(slug: slug, active: true)
  end

  # Render a prompt with variables
  def render(slug, variables = {})
    result = render_with_prompt(slug, variables)
    result[:content] if result
  end

  # Render a prompt with variables and return both content and prompt object
  def render_with_prompt(slug, variables = {})
    prompt = find_prompt(slug)
    return nil unless prompt

    # Render with variables
    content = prompt.render(variables)
    { content: content, prompt: prompt }
  end

  # Create a new prompt
  def create_prompt(name:, description:, content:, category_slug: nil, creator: nil)
    prompt = Prompt.new(
      name: name,
      description: description,
      creator: creator,
      active: true
    )

    if prompt.save
      prompt.update_content(content, "Initial version", creator)
      prompt
    else
      nil
    end
  end

  # Update an existing prompt with a new version
  def update_prompt(slug:, content:, message: nil, user: nil)
    prompt = find_prompt(slug)
    return nil unless prompt

    prompt.create_version(content, message, user)
  end

  # Evaluate a prompt's effectiveness
  def evaluate_prompt(slug:, score:, evaluation_type: "automated", comments: nil, evaluator: nil)
    prompt = find_prompt(slug)
    return nil unless prompt

    # If score is low, we might want to flag the prompt for review
    if score < 0.5
      # Could send a notification or create a task for prompt improvement
      Rails.logger.warn "Low prompt evaluation score (#{score}) for prompt '#{prompt.name}'"
    end

    # Return a hash since PromptEvaluation model is being removed
    { prompt_id: prompt.id, score: score, evaluation_type: evaluation_type, comments: comments }
  end

  # Get prompt usage statistics
  def usage_statistics(slug)
    prompt = find_prompt(slug)
    return nil unless prompt

    # Since PromptUsage is removed, return placeholder data
    # In the future, this can be updated to query LlmCall records with prompt_id
    {
      total_usages: 0,
      by_agent_type: {},
      success_rate: 0.0,
      average_tokens: 0
    }
  end

  # Get all prompts for a specific agent type
  def prompts_for_agent(agent_type)
    # This is a simplified implementation - in a real system, you might have
    # a join table or metadata to associate prompts with specific agent types
    Prompt.active.where("metadata->>'agent_types' @> ?", agent_type.to_json)
  end

  # Convert a module-based prompt to a database prompt
  def import_from_module(module_name, method_name, category_slug: nil, creator: nil)
    # Get the module and method
    mod = module_name.constantize
    return nil unless mod.respond_to?(method_name)

    # Extract method source using Ruby reflection
    method = mod.instance_method(method_name)
    source = method.source

    # Parse the method to extract the prompt content
    # This is a simplified implementation - in a real system, you'd need more robust parsing
    content_match = source.match(/<<~PROMPT(.*?)PROMPT/m)
    return nil unless content_match

    prompt_content = content_match[1].strip

    # Create the prompt
    create_prompt(
      name: "#{module_name.demodulize} - #{method_name.titleize}",
      description: "Imported from #{module_name}##{method_name}",
      content: prompt_content,
      category_slug: category_slug,
      creator: creator
    )
  end

  private
end
