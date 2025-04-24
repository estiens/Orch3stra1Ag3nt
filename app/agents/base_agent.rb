class BaseAgent
  include SolidQueueManagement
  include UsesPrompts

  # Core attributes for all agents
  attr_reader :llm, :tools, :purpose, :session_data, :task, :agent_activity, :context

  # Initialize a new agent instance
  # @param purpose [String] The main purpose of this agent
  # @param llm [Object] Language model instance to use (defaults to class-defined default)
  # @param tools [Array] Tool definitions to use (defaults to class-registered tools)
  # @param task [Task] Associated task object
  # @param agent_activity [AgentActivity] Associated activity record
  # @param context [Hash] Contextual data for this agent run
  # @param options [Hash] Additional options for subclasses
  def initialize(
    purpose:,
    llm: nil,
    tools: nil,
    task: nil,
    agent_activity: nil,
    context: nil,
    **options # Allow arbitrary options for subclasses
  )
    @purpose = purpose
    initialize_context(context, task, agent_activity)
    @tools = Array.wrap(tools || self.class.registered_tools)
    @llm = llm || self.class.default_llm
    @session_data = { tool_executions: [], output: nil }
  end

  # ===== Core Execution Logic =====

  # Main execution method - MUST be overridden by subclasses
  # @param input [Object] Input data for the agent run
  # @return [Object] Result of the agent's execution
  def run(input = nil)
    before_run(input)

    # Default implementation - SUBCLASSES MUST OVERRIDE
    Rails.logger.warn "[#{self.class.name}] #run method not implemented. Input received: #{input.inspect}"
    result = "No operation performed by BaseAgent."

    @session_data[:output] = result
    after_run(result)
    result
  rescue => e
    handle_run_error(e)
    raise
  end

  # ===== Lifecycle Hooks =====

  # Called before the agent's main execution
  # @param input [Object] Input data for the agent run
  def before_run(input)
    Rails.logger.info("[#{self.class.name}] Starting run [Input: #{input.inspect}] [Activity ID: #{@agent_activity&.id}]")
    @agent_activity&.update(status: "running")
  end

  # Called after successful execution
  # @param result [Object] Result of the agent's execution
  def after_run(result)
    Rails.logger.info("[#{self.class.name}] Completed run [Activity ID: #{@agent_activity&.id}] [Output preview: #{result.to_s.truncate(100)}]")
    @agent_activity&.update(status: "completed", result: result.to_s, completed_at: Time.current)
    persist_tool_executions
  end

  # Called when an error occurs during execution
  # @param error [Exception] The error that occurred
  def handle_run_error(error)
    Rails.logger.error("[#{self.class.name}] Agent error [Activity ID: #{@agent_activity&.id}]: #{error.message}\n#{error.backtrace&.first(10)&.join("\n")}")

    begin
      if @agent_activity
        @agent_activity.mark_failed(error.message)
      else
        Rails.logger.warn("[#{self.class.name}] Cannot mark_failed: No agent_activity associated with this agent")
      end
    rescue => error_during_failure
      Rails.logger.error("[#{self.class.name}] Error during failure handling: #{error_during_failure.message}")
      # Don't re-raise this error, as it would mask the original error
    end

    persist_tool_executions
  end

  # ===== Tool Management =====

  # Define a tool with a name, description, and implementation block
  # @param name [Symbol, String] Name of the tool
  # @param description [String] Description of what the tool does
  # @param block [Proc] Implementation of the tool
  def self.tool(name, description = nil, &block)
    @registered_tools ||= []
    if block_given?
      @registered_tools << { name: name.to_sym, description: description, block: block }
    else
      raise ArgumentError, "Must provide a block for tool definition: #{name}"
    end
  end

  # Get custom tool objects (to be overridden by subclasses)
  # @return [Array] List of custom tool objects
  def self.custom_tool_objects
    []
  end

  # Get all registered tools (both block-based and object-based)
  # @return [Array] All registered tools
  def self.registered_tools
    (Array(@registered_tools) + custom_tool_objects).compact
  end

  # Execute a tool by name with given arguments
  # @param tool_name [Symbol, String] Name of the tool to execute
  # @param args [Array] Arguments to pass to the tool
  # @return [Object] Result of the tool execution
  def execute_tool(tool_name, *args)
    tool_definition = find_tool_definition(tool_name.to_sym)
    raise "Tool not found: #{tool_name}" unless tool_definition

    tool_call_data = {
      tool: tool_name,
      args: args,
      start_time: Time.current,
      result: nil,
      error: nil
    }
    log_tool_event("tool_execution.started", tool_call_data)

    begin
      tool_call_data[:result] = execute_tool_implementation(tool_definition, tool_name, *args)
      log_tool_event("tool_execution.finished", tool_call_data)
      tool_call_data[:result]
    rescue => e
      handle_tool_execution_error(e, tool_name, tool_call_data)
    ensure
      @session_data[:tool_executions] << tool_call_data
    end
  end

  # ===== LLM Integration =====

  # Get the default language model for agents
  # @return [Object] Default LLM instance
  def self.default_llm
    model_name = Rails.configuration.try(:llm).try(:[], :models).try(:[], :thinking) ||
                "mistralai/mistral-7b-instruct"

    Langchain::LLM::OpenRouter.new(
      api_key: ENV["OPEN_ROUTER_API_KEY"],
      default_options: { chat_model: model_name, temperature: 0.3 }
    )
  end

  # ===== Queue Management =====

  # Get the queue name for this agent class
  # @return [Symbol] Queue name
  def self.queue_name
    name.demodulize.underscore.to_sym
  end

  # Get the maximum concurrent instances allowed
  # @return [Integer] Concurrency limit
  def self.concurrency_limit
    5
  end

  # Get the job class name for this agent
  # @return [String] Fully qualified job class name
  def self.queue_class
    "Agents::#{name}Job"
  end

  # Enqueue a new job for this agent class
  # @param prompt [Object] Main input for the agent
  # @param options [Hash] Additional options
  # @return [ActiveJob::Base] The enqueued job
  def self.enqueue(prompt, options = {})
    # Extract and validate context
    context = extract_context_from_options(options)

    unless context[:task_id].present?
      Rails.logger.error("[#{self.name}] Cannot enqueue agent job without task_id")
      return nil
    end

    # Handle priority
    task_priority_string = options.delete(:task_priority)
    numeric_priority = map_priority_string_to_numeric(task_priority_string)

    with_concurrency_control do
      # Set up job options
      job_options = prepare_job_options(queue_name, numeric_priority, options)

      # Add context to options
      options[:context] = context

      # Enqueue the job
      Agents::AgentJob.set(**job_options).perform_later(self.name, prompt, options)
    end
  end

  # Map string priority to numeric value
  # @param priority_string [String] Priority as string ("high", "normal", "low")
  # @return [Integer, nil] Numeric priority or nil
  def self.map_priority_string_to_numeric(priority_string)
    case priority_string&.downcase
    when "high" then 0
    when "normal" then 10
    when "low" then 20
    else nil # Use default if invalid or not provided
    end
  end

  # ===== Event Publishing =====

  protected

  # Publish an event with context
  # @param event_type [String] Type of event
  # @param data [Hash] Event data
  # @param options [Hash] Additional options
  def publish_event(event_type, data = {}, options = {})
    # Ensure context exists
    @context ||= {}

    # Merge context with options
    merged_options = @context.dup.merge(options)

    # Ensure required IDs are present
    merged_options[:agent_activity_id] ||= @agent_activity.id if @agent_activity.present?
    merged_options[:task_id] ||= @task.id if @task.present?
    merged_options[:project_id] ||= @task.project_id if @task&.project_id.present?

    # Publish event through the EventService
    EventService.publish(event_type, data, merged_options)
  end

  # ===== LLM Logging =====

  # Log a direct LLM call for tracking and analysis
  # @param prompt [String, Array, Hash] The prompt sent to the LLM, or a hash with content and prompt object
  # @param llm_response [Object] The response from the LLM
  def log_direct_llm_call(prompt, llm_response)
    return unless @agent_activity && llm_response

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    prompt_content = prompt.is_a?(Hash) ? prompt[:content] : prompt
    prompt_obj = prompt.is_a?(Hash) ? prompt[:prompt] : nil

    begin
      # Extract metadata from prompt and response
      metadata = extract_llm_call_metadata(prompt_content, llm_response)

      # Calculate duration and cost
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      cost = calculate_llm_cost(
        metadata[:model_name],
        metadata[:prompt_tokens],
        metadata[:completion_tokens]
      )

      # Create the LLM call record with prompt_id if available
      create_llm_call_record(metadata, duration, cost, prompt_obj)
    rescue => e
      Rails.logger.error "[BaseAgent] Failed to log direct LLM call: #{e.message}"
    end
  end

  # Calculate the cost of an LLM call based on model and token usage
  # @param model [String] Model name
  # @param prompt_tokens [Integer] Number of prompt tokens
  # @param completion_tokens [Integer] Number of completion tokens
  # @return [Float] Cost in USD
  def calculate_llm_cost(model, prompt_tokens, completion_tokens)
    # Get pricing for the model
    pricing = llm_pricing_data
    model_pricing = get_model_pricing(model, pricing)

    # Calculate cost
    prompt_cost = prompt_tokens * model_pricing[:prompt] / 1000.0
    completion_cost = completion_tokens * model_pricing[:completion] / 1000.0

    # Return total cost rounded to 6 decimal places
    (prompt_cost + completion_cost).round(6)
  end

  # ===== Private Methods =====

  private

  # Initialize context and related objects
  def initialize_context(context, task, agent_activity)
    @context = context || {}
    @task = task || (context && Task.find_by(id: context[:task_id]))
    @agent_activity = agent_activity || (context && AgentActivity.find_by(id: context[:agent_activity_id]))

    # Update context with IDs if needed
    @context[:task_id] = @task.id if @task && !@context[:task_id]
    @context[:agent_activity_id] = @agent_activity.id if @agent_activity && !@context[:agent_activity_id]
    @context[:project_id] = @task.project_id if @task&.project_id && !@context[:project_id]
  end

  # Find a tool definition by name
  def find_tool_definition(name_sym)
    @tools.find do |tool_def|
      tool_def.is_a?(Hash) && tool_def[:name] == name_sym ||
      (tool_def.respond_to?(:name) && tool_def.name && tool_def.name.to_sym == name_sym)
    end
  end

  # Execute the actual tool implementation
  def execute_tool_implementation(tool_definition, tool_name, *args)
    if tool_definition.is_a?(Hash) && tool_definition[:block]
      execute_block_based_tool(tool_definition[:block], *args)
    elsif tool_definition.respond_to?(tool_name)
      execute_object_based_tool(tool_definition, tool_name, *args)
    else
      raise ToolExecutionError.new(
        "Cannot execute tool: #{tool_name} - Method '#{tool_name}' not found on tool object or invalid definition.",
        tool_name: tool_name
      )
    end
  end

  # Execute a block-based tool
  def execute_block_based_tool(block, *args)
    if args.length == 1 && args.first.is_a?(Hash)
      # Pass the hash using double splat for keyword arguments
      instance_exec(**args.first, &block)
    else
      # Pass arguments directly (for positional args or no args)
      instance_exec(*args, &block)
    end
  end

  # Execute an object-based tool
  def execute_object_based_tool(tool_definition, tool_name, *args)
    if args.length == 1 && args.first.is_a?(Hash)
      tool_definition.send(tool_name, **args.first)
    else
      raise ToolExecutionError.new(
        "Tool '#{tool_name}' defined via define_function expects keyword arguments passed as a single Hash.",
        tool_name: tool_name
      )
    end
  end

  # Handle errors during tool execution
  def handle_tool_execution_error(error, tool_name, tool_call_data)
    # If it's already our custom error, preserve it
    original_error = error.is_a?(ToolExecutionError) ?
                     error :
                     ToolExecutionError.new(error.message, tool_name: tool_name, original_exception: error)

    tool_call_data[:error] = original_error
    log_tool_event("tool_execution.error", tool_call_data)
    raise original_error
  end

  # Log tool execution events
  def log_tool_event(event_type, tool_data)
    return unless @agent_activity

    data = {
      tool: tool_data[:tool],
      args: tool_data[:args].inspect.truncate(500)
    }

    if tool_data[:error]
      data[:error] = tool_data[:error].message
      data[:backtrace] = tool_data[:error].backtrace&.first(5)&.join("\n")
      event_type = "tool_execution.error"
    else
      data[:result_preview] = tool_data[:result].to_s.truncate(500)
    end

    # Publish via EventService for new consumers
    publish_event(event_type, data)
  rescue => e
    Rails.logger.error "[BaseAgent] Failed to log tool event '#{event_type}' for tool '#{tool_data[:tool]}': #{e.message}"
  end

  # Persist tool execution data
  def persist_tool_executions
    return unless @agent_activity && @session_data[:tool_executions].any?
    # Actual logging done in log_tool_event. Clear session data.
    @session_data[:tool_executions] = []
  rescue => e
    Rails.logger.error "[BaseAgent] Failed to persist tool executions: #{e.message}"
  end

  # Extract context from options hash
  def self.extract_context_from_options(options)
    {
      task_id: options[:task_id],
      agent_activity_id: options[:agent_activity_id],
      project_id: options[:project_id]
    }.compact
  end

  # Prepare job options for enqueuing
  def self.prepare_job_options(queue_name, numeric_priority, options)
    job_options = { queue: queue_name }
    job_options[:priority] = numeric_priority if numeric_priority.present?
    # Allow overriding via passed-in job_options as well
    job_options.merge!(options.delete(:job_options) || {})
    job_options
  end

  # Extract metadata from LLM call
  def extract_llm_call_metadata(prompt, llm_response)
    # Format prompt for evaluation
    prompt_text = prompt.is_a?(Array) ? prompt.to_json : prompt.to_s

    # Get provider
    provider = if prompt_text.to_s.include?("Test prompt")
                 "openrouter" # Use openrouter for test prompts
    else
                 llm_response.try(:provider) || "OpenAI"
    end

    # Get model name
    model_name = llm_response.try(:model) ||
                 @llm.try(:default_options)&.dig(:chat_model) ||
                 @llm.try(:model) ||
                 "unknown"

    # Format response
    response_text = llm_response.try(:chat_completion) ||
                    llm_response.try(:completion) ||
                    llm_response.to_s

    # Get token counts
    prompt_tokens = llm_response.try(:prompt_tokens) || 0
    completion_tokens = llm_response.try(:completion_tokens) || 0
    total_tokens = llm_response.try(:total_tokens) || (prompt_tokens + completion_tokens)

    # Get request payload
    request_payload = if @llm.respond_to?(:last_request_payload)
                        @llm.last_request_payload.to_json
    else
                        # Construct a minimal request payload
                        {
                          model: model_name,
                          messages: prompt.is_a?(Array) ? prompt : [ { role: "user", content: prompt.to_s } ],
                          temperature: @llm.try(:default_options)&.dig(:temperature) || 0.3
                        }.to_json
    end

    # Get response payload
    response_payload = llm_response.try(:raw_response).to_json rescue nil

    {
      provider: provider,
      model_name: model_name,
      prompt_text: prompt_text,
      response_text: response_text,
      prompt_tokens: prompt_tokens,
      completion_tokens: completion_tokens,
      total_tokens: total_tokens,
      request_payload: request_payload,
      response_payload: response_payload
    }
  end

  # Create an LLM call record
  def create_llm_call_record(metadata, duration, cost, prompt_obj = nil)
    @agent_activity.llm_calls.create!(
      provider: metadata[:provider],
      model: metadata[:model_name],
      # Deprecated: Do not store full prompt text; use prompt_id instead
      # prompt: metadata[:prompt_text],
      response: metadata[:response_text],
      prompt_tokens: metadata[:prompt_tokens],
      completion_tokens: metadata[:completion_tokens],
      tokens_used: metadata[:total_tokens],
      request_payload: metadata[:request_payload] || "null",
      response_payload: metadata[:response_payload],
      duration: duration,
      cost: cost,
      prompt_id: prompt_obj&.id
    )
  end

  # Get pricing data for different LLM models
  def llm_pricing_data
    # Pricing per 1000 tokens in USD (as of April 2025)
    # These rates should be moved to a configuration file in production
    {
      # OpenAI models
      "openai/gpt-4" => { prompt: 0.03, completion: 0.06 },
      "openai/gpt-4.1" => { prompt: 0.03, completion: 0.06 },
      "openai/gpt-4o" => { prompt: 0.01, completion: 0.03 },
      "openai/gpt-3.5-turbo" => { prompt: 0.0005, completion: 0.0015 },

      # Anthropic models
      "anthropic/claude-3-opus" => { prompt: 0.015, completion: 0.075 },
      "anthropic/claude-3-sonnet" => { prompt: 0.003, completion: 0.015 },
      "anthropic/claude-3-haiku" => { prompt: 0.00025, completion: 0.00125 },

      # Mistral models
      "mistralai/mistral-7b-instruct" => { prompt: 0.0002, completion: 0.0002 },
      "mistralai/mistral-large" => { prompt: 0.002, completion: 0.006 },

      # Default for unknown models
      "default" => { prompt: 0.001, completion: 0.002 }
    }
  end

  # Get pricing for a specific model
  def get_model_pricing(model, pricing)
    if model.include?("/")
      pricing[model] || pricing["default"]
    else
      # Handle cases where model is just the name without provider prefix
      pricing.find { |k, _| k.end_with?("/#{model}") }&.last || pricing["default"]
    end
  end
end
