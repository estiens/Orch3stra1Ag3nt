class BaseAgent
  include SolidQueueManagement
  # Optionally include EventSubscriber or pass to subclasses

  attr_reader :llm, :tools, :purpose, :session_data, :task, :agent_activity
  # Removed :chain, :retriever

  def initialize(
    purpose:,
    llm: nil,
    tools: nil,
    task: nil,
    agent_activity: nil,
    **options # Allow arbitrary options for subclasses
  )
    @purpose = purpose
    @task = task
    @agent_activity = agent_activity
    # Tools are stored internally as an array of hashes (for blocks) or objects
    @tools = Array.wrap(tools || self.class.registered_tools)
    @llm = llm || self.class.default_llm
    @session_data = { tool_executions: [], output: nil }

    # No chain setup needed
  end

  # --- Tool Definition ---
  def self.tool(name, description = nil, &block)
    @registered_tools ||= []
    if block_given?
      @registered_tools << { name: name.to_sym, description: description, block: block }
    else
      raise ArgumentError, "Must provide a block for tool definition: #{name}"
    end
  end

  def self.custom_tool_objects
    []
  end

  def self.registered_tools
    (Array(@registered_tools) + custom_tool_objects).compact
  end
  # --- End Tool Definition ---

  # Default LLM
  def self.default_llm
    model_name = Rails.configuration.try(:llm).try(:[], :models).try(:[], :thinking) || "mistralai/mistral-7b-instruct"
    Langchain::LLM::OpenRouter.new(
      api_key: ENV["OPEN_ROUTER_API_KEY"],
      default_options: { chat_model: model_name, temperature: 0.3 }
    )
  end

  # --- Tool Execution & Logging ---
  # Helper method to execute a defined tool and log it
  def execute_tool(tool_name, *args)
    tool_definition = find_tool_definition(tool_name.to_sym)
    raise "Tool not found: #{tool_name}" unless tool_definition

    tool_call_data = { tool: tool_name, args: args, start_time: Time.current, result: nil, error: nil }
    log_tool_event("tool_execution_started", tool_call_data)

    begin
      result = if tool_definition.is_a?(Hash) && tool_definition[:block]
                 # Execute block-based tool in instance context
                 # Check if args contains a single hash, indicative of keyword arguments
                 if args.length == 1 && args.first.is_a?(Hash)
                   # Pass the hash using double splat for keyword arguments
                   instance_exec(**args.first, &tool_definition[:block])
                 else
                   # Pass arguments directly (for positional args or no args)
                   instance_exec(*args, &tool_definition[:block])
                 end

      elsif tool_definition.respond_to?(tool_name) # Check if the object has the method matching tool_name
                 # Handles tools defined using `define_function :method_name`
                 # Assumes keyword arguments passed as a single hash
                 if args.length == 1 && args.first.is_a?(Hash)
                   tool_definition.send(tool_name, **args.first) # Use .send to call dynamically
                 else
                   # If args are not a hash, try calling directly (might work for simple positional args)
                   # Consider raising an error if strict kwarg adherence is required.
                   # For now, let's raise for clarity as define_function usually implies kwargs.
                   # Raise our custom error for argument issues
                   raise ToolExecutionError.new(
                     "Tool '#{tool_name}' defined via define_function expects keyword arguments passed as a single Hash.",
                     tool_name: tool_name
                   )
                 end
      # Optional: Add checks for .execute or .call if other tool patterns are needed
      # elsif tool_definition.respond_to?(:execute)
      #   # ... logic ...
      else
                 # Raise our custom error for definition issues
                 raise ToolExecutionError.new(
                   "Cannot execute tool: #{tool_name} - Method '#{tool_name}' not found on tool object or invalid definition.",
                   tool_name: tool_name
                 )
      end

      tool_call_data[:result] = result
      log_tool_event("tool_execution_finished", tool_call_data)
      result
    rescue => e
      # If it's already our custom error, preserve it
      original_error = e.is_a?(ToolExecutionError) ? e : ToolExecutionError.new(e.message, tool_name: tool_name, original_exception: e)

      tool_call_data[:error] = original_error # Log the (potentially wrapped) error
      log_tool_event("tool_execution_error", tool_call_data)
      raise original_error # Re-raise the (potentially wrapped) error
    ensure
      @session_data[:tool_executions] << tool_call_data
    end
  end
  # --- End Tool Execution & Logging ---

  # Removed setup_chain! method

  # --- Core Execution ---
  # This method MUST be overridden by subclasses to implement the agent's
  # specific logic, such as calling LLMs, using tools via `execute_tool`,
  # managing state, etc.
  # The `input` argument will typically contain the task details (title, description)
  # and any specific instructions passed during enqueue.
  def run(input = nil)
    before_run(input)

    # Default implementation does nothing useful - SUBCLASSES MUST OVERRIDE.
    Rails.logger.warn "[#{self.class.name}] #run method not implemented. Input received: #{input.inspect}"
    result = "No operation performed by BaseAgent." # Default result

    @session_data[:output] = result
    after_run(result)
    result
  rescue => e
    handle_run_error(e)
    raise
  end
  # --- End Core Execution ---

  # --- Lifecycle Hooks & Base Logging ---
  def before_run(input)
    Rails.logger.info("[#{self.class.name}] Starting run [Input: #{input.inspect}] [Activity ID: #{@agent_activity&.id}]")
    @agent_activity&.update(status: "running")
  end

  def after_run(result)
    Rails.logger.info("[#{self.class.name}] Completed run [Activity ID: #{@agent_activity&.id}] [Output preview: #{result.to_s.truncate(100)}]")
    @agent_activity&.update(status: "finished")
    persist_tool_executions
  end

  def handle_run_error(e)
    Rails.logger.error("[#{self.class.name}] Agent error [Activity ID: #{@agent_activity&.id}]: #{e.message}\n#{e.backtrace.first(10).join("\n")}")
    @agent_activity&.mark_failed(e.message)
    persist_tool_executions
  end
  # --- End Lifecycle Hooks & Base Logging ---

  # --- SolidQueue Integration ---
  def self.queue_name
    name.demodulize.underscore.to_sym
  end

  def self.concurrency_limit
    5
  end

  def self.queue_class
    "Agents::#{name}Job"
  end

  def self.enqueue(prompt, options = {})
    task_priority_string = options.delete(:task_priority) # Get priority string if passed
    numeric_priority = map_priority_string_to_numeric(task_priority_string) # Implement this mapping

    with_concurrency_control do
      agent_class_name = self.name
      # Add numeric_priority to job_options if it's valid
      job_options = { queue: queue_name }
      job_options[:priority] = numeric_priority if numeric_priority.present?
      # Allow overriding via passed-in job_options as well
      job_options.merge!(options.delete(:job_options) || {})

      Agents::AgentJob.set(job_options).perform_later(agent_class_name, prompt, options)
    end
  end

  # --- Helper for Priority Mapping ---
  def self.map_priority_string_to_numeric(priority_string)
    case priority_string&.downcase
    when "high" then 0
    when "normal" then 10
    when "low" then 20
    else nil # Use default if invalid or not provided
    end
  end
  # --- End Helper ---
  # --- End SolidQueue Integration ---

  # --- Protected Logging Helpers ---
  protected

  # Use this in subclasses when making direct LLM calls to log them
  def log_direct_llm_call(prompt, llm_response)
    return unless @agent_activity && llm_response
    begin
      model_name = @llm.try(:default_options)&.dig(:chat_model) || @llm.try(:model) || "unknown"
      provider = "openrouter" # TODO: Make provider dynamic if needed

      prompt_text = prompt.is_a?(Array) ? prompt.to_json : prompt.to_s
      response_text = llm_response.try(:chat_completion) || llm_response.try(:completion) || llm_response.to_s
      prompt_tokens = llm_response.try(:prompt_tokens) || 0
      completion_tokens = llm_response.try(:completion_tokens) || 0
      total_tokens = llm_response.try(:total_tokens) || (prompt_tokens + completion_tokens)

      @agent_activity.llm_calls.create!(
        provider: provider,
        model: model_name,
        prompt: prompt_text,
        response: response_text,
        prompt_tokens: prompt_tokens,
        completion_tokens: completion_tokens,
        tokens_used: total_tokens
      )
    rescue => e
      Rails.logger.error "[BaseAgent] Failed to log direct LLM call: #{e.message}"
    end
  end
  # --- End Protected Logging Helpers ---

  # --- Private Methods ---
  private

  def find_tool_definition(name_sym)
    @tools.find do |tool_def|
      if tool_def.is_a?(Hash)
        tool_def[:name] == name_sym
      elsif tool_def.respond_to?(:name) && tool_def.name # Check name exists
        tool_def.name.to_sym == name_sym
      else
        false
      end
    end
  end

  def log_tool_event(event_type, tool_data)
    return unless @agent_activity
    data = { tool: tool_data[:tool], args: tool_data[:args].inspect.truncate(500) }
    if tool_data[:error]
      data[:error] = tool_data[:error].message
      data[:backtrace] = tool_data[:error].backtrace&.first(5)&.join("\n")
      event_type = "tool_execution_error"
    else
      data[:result_preview] = tool_data[:result].to_s.truncate(500)
    end
    @agent_activity.events.create!(event_type: event_type, data: data)
  rescue => e
    Rails.logger.error "[BaseAgent] Failed to log tool event '#{event_type}' for tool '#{tool_data[:tool]}': #{e.message}"
  end

  def persist_tool_executions
    return unless @agent_activity && @session_data[:tool_executions].any?
    # Actual logging done in log_tool_event. Clear session data.
    @session_data[:tool_executions] = []
  rescue => e
    Rails.logger.error "[BaseAgent] Failed to persist tool executions: #{e.message}"
  end
  # --- End Private Methods ---
end
