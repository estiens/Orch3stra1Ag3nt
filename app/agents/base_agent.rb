# BaseAgent: Inherit from this for per-agent queue and model config

class BaseAgent
  include SolidQueueManagement

  attr_accessor :task, :agent_activity, :chain, :llm, :session_data

  def initialize(purpose, **kwargs)
    # Store task and agent_activity if provided
    @task = kwargs.delete(:task)
    @agent_activity = kwargs.delete(:agent_activity)
    @session_data = { llm_calls: [], tool_executions: [], result: nil }

    # Set up the LLM based on provided model or default
    model_param = kwargs.delete(:model)
    @llm = initialize_llm(model_param)
    
    # Initialize purpose
    @purpose = purpose
    
    # Initialize tools registry
    @tools = {}
    
    # Register any tools defined in the class
    register_class_tools
  end
  
  def run(input = nil)
    before_run
    
    begin
      # Execute the agent's chain
      result = execute_chain(input)
      @session_data[:result] = result
      
      after_run
      return result
    rescue => e
      Rails.logger.error("Agent error: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      
      if @agent_activity
        @agent_activity.mark_failed(e.message)
      end
      
      raise e
    end
  end
  
  def execute_chain(input)
    # Override in subclasses to implement specific chain execution
    raise NotImplementedError, "Subclasses must implement execute_chain"
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
  
  # Tool registration and execution
  def self.tool(name, description = nil, &block)
    @tools ||= {}
    @tools[name] = { description: description, block: block }
  end
  
  def self.tools
    @tools || {}
  end
  
  def register_class_tools
    self.class.tools.each do |name, tool_info|
      @tools[name] = tool_info
    end
  end
  
  def execute_tool(name, *args)
    tool = @tools[name.to_sym]
    raise "Tool not found: #{name}" unless tool
    
    result = instance_exec(*args, &tool[:block])
    
    # Record tool execution
    @session_data[:tool_executions] << {
      tool: name,
      args: args,
      result: result
    }
    
    result
  end

  # Common model definitions - can be referenced as :fast, :thinking, etc.
  def fast_model
    Langchain::LLM::OpenRouter.new(
      api_key: ENV["OPEN_ROUTER_API_KEY"],
      default_options: {
        chat_model: LANGCHAIN_MODEL_DEFAULTS[:fast] || "anthropic/claude-3-haiku-20240307",
        temperature: 0.2
      }
    )
  end

  def thinking_model
    Langchain::LLM::OpenRouter.new(
      api_key: ENV["OPEN_ROUTER_API_KEY"],
      default_options: {
        chat_model: LANGCHAIN_MODEL_DEFAULTS[:thinking] || "anthropic/claude-3-sonnet-20240229",
        temperature: 0.3
      }
    )
  end

  def multimodal_model
    Langchain::LLM::OpenRouter.new(
      api_key: ENV["OPEN_ROUTER_API_KEY"],
      default_options: {
        chat_model: LANGCHAIN_MODEL_DEFAULTS[:multimodal] || "anthropic/claude-3-opus-20240229",
        temperature: 0.2
      }
    )
  end

  def edge_model
    Langchain::LLM::OpenRouter.new(
      api_key: ENV["OPEN_ROUTER_API_KEY"],
      default_options: {
        chat_model: "anthropic/claude-3-haiku-20240307",
        temperature: 0.1
      }
    )
  end

  # Default model if none specified
  def self.default_model
    LANGCHAIN_MODEL_DEFAULTS[:thinking] || "anthropic/claude-3-sonnet-20240229"
  end

  def default_model
    Langchain::LLM::OpenRouter.new(
      api_key: ENV["OPEN_ROUTER_API_KEY"],
      default_options: {
        chat_model: self.class.default_model,
        temperature: 0.3
      }
    )
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

    # Record activity data if agent_activity is present
    if @agent_activity
      # Record the LLM call details
      @session_data[:llm_calls].each do |llm_call|
        @agent_activity.llm_calls.create!(
          provider: llm_call[:provider] || "openrouter",
          model: llm_call[:model],
          prompt: llm_call[:input],
          response: llm_call[:output],
          tokens_used: llm_call[:tokens] || 0
        )
      end

      # Record tool executions if any
      @session_data[:tool_executions].each do |tool_exec|
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
  
  private
  
  def initialize_llm(model_param)
    if model_param.is_a?(Langchain::LLM::Base)
      # Use the LLM instance as is
      model_param
    elsif model_param.is_a?(Symbol) && respond_to?("#{model_param}_model")
      # Use a predefined model type (fast, thinking, etc)
      send("#{model_param}_model")
    elsif model_param.is_a?(String)
      # Create a new LLM instance with the given model name
      Langchain::LLM::OpenRouter.new(
        api_key: ENV["OPEN_ROUTER_API_KEY"],
        default_options: {
          chat_model: model_param,
          temperature: 0.3
        }
      )
    else
      # Fall back to default model
      default_model
    end
  end
  
  def record_llm_call(provider, model, input, output, tokens = 0)
    @session_data[:llm_calls] << {
      provider: provider || "openrouter",
      model: model,
      input: input,
      output: output,
      tokens: tokens
    }
  end
end
