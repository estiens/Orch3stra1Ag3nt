# BaseAgent: Inherit from this for per-agent queue and model config

class BaseAgent < Regent::Agent
  include SolidQueueManagement

  attr_accessor :task, :agent_activity

  def initialize(purpose, **kwargs)
    # Store task and agent_activity if provided
    @task = kwargs.delete(:task)
    @agent_activity = kwargs.delete(:agent_activity)

    # Always pass a model kwarg: user-supplied or default_model
    # Try to use provided model name or LLM instance, fall back to default_model
    model_param = kwargs.delete(:model)

    if model_param.is_a?(Regent::LLM)
      # Use the LLM instance as is
      model = model_param
    elsif model_param.is_a?(Symbol) && respond_to?("#{model_param}_model")
      # Use a predefined model type (fast, thinking, etc)
      model = send("#{model_param}_model")
    elsif model_param.is_a?(String)
      # Create a new LLM instance with the given model name
      model = Regent::LLM.new(model_param)
    else
      # Fall back to default model
      model = default_model
    end

    super(purpose, model: model, **kwargs)
  end

  def self.queue_name
    name.demodulize.underscore.to_sym
  end

  # Queue concurrency - override in subclass if needed
  def self.concurrency_limit
    5
  end

  # Helper method to get the queue class - useful for SolidQueue config
  def self.queue_class
    "Agents::#{name}Job"
  end

  # Method to create a job for this agent type
  def self.enqueue(prompt, options = {})
    with_concurrency_control do
      Agents::AgentJob.set(queue: queue_name).perform_later(self.name, prompt, options)
    end
  end

  # Common model definitions - can be referenced as :fast, :thinking, etc.
  def fast_model
    Regent::LLM.new("deepseek/deepseek-chat-v3-0324", temperature: 0.2)
  end

  def thinking_model
    Regent::LLM.new("deepseek/deepseek-chat-v3-0324", temperature: 0.3)
  end

  def multimodal_model
    Regent::LLM.new("anthropic/claude-3-opus-20240229", temperature: 0.2)
  end

  def edge_model
    Regent::LLM.new("anthropic/claude-3-haiku-20240307", temperature: 0.1)
  end

  # Default model if none specified
  def self.default_model
    "deepseek/deepseek-chat-v3-0324"
  end

  def default_model
    Regent::LLM.new(self.class.default_model, temperature: 0.3)
  end

  # Override this in subclasses for pre-run setup
  # This is called before the agent starts processing
  def before_run
    Rails.logger.info("Agent #{self.class.name} starting run")

    # Update agent_activity if present
    if @agent_activity
      @agent_activity.update(status: "running", started_at: Time.current)
    end
  end

  # Override this in subclasses for post-run actions
  # This is called after the agent completes processing
  def after_run
    Rails.logger.info("Agent #{self.class.name} completed run")

    # Capture session info if possible
    if session_trace && @agent_activity
      # Record the LLM call details
      session_trace.llm_calls.each do |llm_call|
        @agent_activity.llm_calls.create!(
          provider: llm_call[:provider] || "openrouter",
          model: llm_call[:model] || default_model,
          prompt: llm_call[:input],
          response: llm_call[:output],
          tokens_used: llm_call[:tokens] || 0
        )
      end

      # Record tool executions if any
      session_trace.tool_executions.each do |tool_exec|
        @agent_activity.events.create!(
          event_type: "tool_execution",
          data: {
            tool: tool_exec[:tool],
            args: tool_exec[:args],
            result: tool_exec[:result]
          }
        )
      end
    end
  end

  # Session trace helper - formats the session information in a structured way
  def session_trace
    return nil unless session

    @session_trace ||= {
      llm_calls: extract_llm_calls,
      tool_executions: extract_tool_executions,
      result: session.result
    }
  end

  private

  # Extract all LLM calls from the session
  def extract_llm_calls
    return [] unless session&.spans

    session.spans.select { |span| span.type == Regent::Span::Type::LLM_CALL }.map do |span|
      {
        provider: "openrouter",
        model: span.arguments[:model],
        input: span.arguments[:message],
        output: span.output,
        tokens: span.meta&.dig(:input_tokens).to_i + span.meta&.dig(:output_tokens).to_i
      }
    end
  end

  # Extract all tool executions from the session
  def extract_tool_executions
    return [] unless session&.spans

    session.spans.select { |span| span.type == Regent::Span::Type::TOOL_EXECUTION }.map do |span|
      {
        tool: span.arguments[:name],
        args: span.arguments[:arguments],
        result: span.output
      }
    end
  end
end
