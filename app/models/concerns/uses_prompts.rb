# frozen_string_literal: true

# UsesPrompts: Concern for models that use prompts
# Provides methods for accessing and using prompts via PromptService
module UsesPrompts
  extend ActiveSupport::Concern

  included do
    # Instance methods

    # Get a prompt service instance for this agent
    def prompt_service
      @prompt_service ||= PromptService.new(self.class.name, agent_activity)
    end

    # Render a prompt with variables
    def render_prompt(slug, variables = {})
      result = prompt_service.render_with_prompt(slug, variables)

      # If prompt not found in database, fall back to module-based prompts
      if result.nil? && respond_to?(slug, true)
        # Call the method on the instance
        prompt_content = send(slug, **variables)
        return { content: prompt_content, prompt: nil }
      end

      result || { content: nil, prompt: nil }
    end

    # Evaluate a prompt's effectiveness
    def evaluate_prompt(slug, score, options = {})
      prompt_service.evaluate_prompt(
        slug: slug,
        score: score,
        evaluation_type: options[:evaluation_type] || "automated",
        comments: options[:comments],
        evaluator: options[:evaluator]
      )
    end
  end

  class_methods do
    # Class methods

    # Get all prompts for this agent type
    def available_prompts
      PromptService.new(name).prompts_for_agent(name)
    end

    # Import prompts from a module
    def import_prompts_from_module(module_name, category_slug = nil, creator = nil)
      mod = module_name.constantize

      # Get all instance methods that could be prompts
      prompt_methods = mod.instance_methods(false).select do |method_name|
        # Simple heuristic: method name ends with _prompt
        method_name.to_s.end_with?("_prompt")
      end

      service = PromptService.new
      imported = []

      prompt_methods.each do |method_name|
        prompt = service.import_from_module(module_name, method_name, category_slug: category_slug, creator: creator)
        imported << prompt if prompt
      end

      imported
    end
  end
end
