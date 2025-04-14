# require "langchain/callbacks/base_callback_handler"

# Custom callback handler to record LLM calls and tool executions
# to the AgentActivity model.
class AgentActivityCallbackHandler < Langchain::Callbacks::BaseCallbackHandler
  attr_reader :agent_activity

  # Only handle these events
  EVENTS = [
    :on_llm_start,
    :on_llm_end,
    :on_tool_start,
    :on_tool_end,
    :on_tool_error,
    :on_chain_end, # Useful for final status?
    :on_chain_error # Useful for marking failure?
  ]

  def initialize(agent_activity:)
    @agent_activity = agent_activity
    # Ensure methods for handled events exist
    EVENTS.each do |event|
      unless respond_to?(event, true)
        define_singleton_method(event) { |*_args, **_kwargs| }
      end
    end
  end

  # --- LLM Callbacks ---
  def on_llm_start(serialized, prompts, **kwargs)
    # Store the prompt temporarily if needed, maybe for matching with the end call
    # For now, we primarily record on_llm_end
    Rails.logger.debug "[Callback][#{agent_activity&.id}] LLM Start: #{serialized[:name]}"
  end

  def on_llm_end(response, **kwargs)
    return unless agent_activity

    # Extract relevant data from the response object
    # The structure might vary slightly depending on the LLM provider wrapper
    provider = response.try(:provider) || "openrouter" # Default provider
    model_name = response.try(:model) || response.try(:model_name) || serialized.dig(:invocation_params, :model_name) || "unknown"
    prompt = response.try(:prompt) || "(prompt unavailable)"
    response_text = response.try(:completion) || response.try(:chat_completion) || response.try(:content) || "(response unavailable)"
    prompt_tokens = response.try(:prompt_tokens) || 0
    completion_tokens = response.try(:completion_tokens) || 0
    total_tokens = response.try(:total_tokens) || (prompt_tokens + completion_tokens)

    begin
      agent_activity.llm_calls.create!(
        provider: provider,
        model: model_name,
        prompt: prompt.is_a?(Array) ? prompt.to_json : prompt.to_s, # Handle different prompt formats
        response: response_text.to_s,
        tokens_used: total_tokens,
        prompt_tokens: prompt_tokens,
        completion_tokens: completion_tokens
      )
      Rails.logger.debug "[Callback][#{agent_activity.id}] LLM End Recorded: #{model_name}, Tokens: #{total_tokens}"
    rescue => e
      Rails.logger.error "[Callback][#{agent_activity.id}] Failed to record LLM Call: #{e.message}"
    end
  end

  # --- Tool Callbacks ---
  def on_tool_start(serialized, input_str, **kwargs)
    return unless agent_activity
    tool_name = serialized.dig(:name) || "unknown_tool"
    Rails.logger.debug "[Callback][#{agent_activity.id}] Tool Start: #{tool_name}, Input: #{input_str.inspect}"
    # Store start time or details if needed for on_tool_end
  end

  def on_tool_end(output, **kwargs)
    return unless agent_activity
    # Need tool name from context, assuming kwargs might hold it or we need to track from on_tool_start
    tool_name = kwargs.dig(:tool_name) || kwargs.dig(:name) || "unknown_tool" # Adjust based on actual kwargs

    begin
      # Sanitize output for storage if necessary
      sanitized_output = output.to_s.truncate(10000) # Limit size

      agent_activity.events.create!(
        event_type: "tool_execution",
        data: {
          tool: tool_name,
          # Input might need to be tracked from on_tool_start
          input: kwargs.dig(:input_str) || "(input unavailable)",
          result_preview: sanitized_output.truncate(200)
          # Avoid storing excessively large results directly in the event
          # Consider storing large results elsewhere if needed
          # result: sanitized_output # Optionally store truncated result
        }
      )
      Rails.logger.debug "[Callback][#{agent_activity.id}] Tool End Recorded: #{tool_name}"
    rescue => e
      Rails.logger.error "[Callback][#{agent_activity.id}] Failed to record Tool Execution event: #{e.message}"
    end
  end

  def on_tool_error(error, **kwargs)
    return unless agent_activity
    tool_name = kwargs.dig(:tool_name) || kwargs.dig(:name) || "unknown_tool"

    begin
      agent_activity.events.create!(
        event_type: "tool_error",
        data: {
          tool: tool_name,
          input: kwargs.dig(:input_str) || "(input unavailable)",
          error: error.message,
          backtrace: error.backtrace&.first(5)&.join("\n")
        }
      )
      Rails.logger.error "[Callback][#{agent_activity.id}] Tool Error Recorded: #{tool_name} - #{error.message}"
    rescue => e
      Rails.logger.error "[Callback][#{agent_activity.id}] Failed to record Tool Error event: #{e.message}"
    end
  end

  # --- Chain Callbacks ---
  def on_chain_end(outputs, **kwargs)
    # Potentially update final status here, but BaseAgent#after_run already handles 'finished'
    Rails.logger.debug "[Callback][#{agent_activity&.id}] Chain End."
  end

  def on_chain_error(error, **kwargs)
    # BaseAgent#handle_run_error already calls mark_failed
    Rails.logger.error "[Callback][#{agent_activity&.id}] Chain Error: #{error.message}"
  end

  # Ignore other events by default
  def method_missing(method_name, *args, **kwargs)
    if EVENTS.include?(method_name)
      # If we defined a handler but it got removed, this prevents errors
      # Or if we just want to explicitly ignore some defined events
      Rails.logger.debug "[Callback][#{agent_activity&.id}] Unhandled Event: #{method_name}"
    else
      # Pass up the chain for genuinely missing methods
      super
    end
  end

  def respond_to_missing?(method_name, include_private = false)
    EVENTS.include?(method_name) || super
  end
end
