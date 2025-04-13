# ToolRegistry: Central registry for all available tools in the system
# Manages tool registration, discovery, and metadata
class ToolRegistry
  include Singleton

  # Class methods - delegates to instance
  class << self
    delegate :register, :unregister, :get_tool, :all_tools,
             :tools_for_category, :register_tool_class, to: :instance
  end

  def initialize
    @tools = {}
    @tool_classes = {}
    @mutex = Mutex.new
  end

  # Register a tool with the registry
  # @param name [Symbol] The unique name of the tool
  # @param metadata [Hash] Metadata about the tool including description, category, etc.
  # @param implementation [Proc, Class] The implementation of the tool
  def register(name, metadata = {}, implementation = nil)
    name = name.to_sym

    @mutex.synchronize do
      if @tools.key?(name)
        Rails.logger.warn("Tool '#{name}' is being re-registered")
      end

      @tools[name] = {
        name: name,
        description: metadata[:description] || "No description provided",
        category: metadata[:category] || :general,
        parameters: metadata[:parameters] || [],
        input_schema: metadata[:input_schema],
        output_schema: metadata[:output_schema],
        implementation: implementation,
        registered_at: Time.current
      }
    end

    Rails.logger.info("Registered tool: #{name} in category #{metadata[:category] || :general}")

    true
  end

  # Register a tool class with the registry
  # @param tool_class [Class] The class that inherits from BaseTool
  def register_tool_class(tool_class)
    unless tool_class < BaseTool
      raise ArgumentError, "Tool class must inherit from BaseTool"
    end

    @mutex.synchronize do
      @tool_classes[tool_class.name] = tool_class

      # Also register each tool provided by this class
      tool_class.provided_tools.each do |tool_name, metadata|
        register(
          tool_name,
          metadata.merge(implementation: tool_class)
        )
      end
    end

    true
  end

  # Unregister a tool from the registry
  # @param name [Symbol] The name of the tool to unregister
  def unregister(name)
    name = name.to_sym

    @mutex.synchronize do
      if @tools.delete(name)
        Rails.logger.info("Unregistered tool: #{name}")
        return true
      end
    end

    false
  end

  # Get a tool by name
  # @param name [Symbol] The name of the tool to get
  # @return [Hash, nil] The tool metadata and implementation, or nil if not found
  def get_tool(name)
    name = name.to_sym
    @tools[name]
  end

  # Get all registered tools
  # @return [Hash] All registered tools
  def all_tools
    @tools.dup
  end

  # Get all tools in a specific category
  # @param category [Symbol] The category to filter by
  # @return [Hash] All tools in the specified category
  def tools_for_category(category)
    category = category.to_sym
    @tools.select { |_, tool| tool[:category] == category }
  end

  # Execute a tool by name
  # @param name [Symbol] The name of the tool to execute
  # @param args [Hash] The arguments to pass to the tool
  # @param context [Object] Optional context object for the tool execution
  # @return [Object] The result of the tool execution
  def execute(name, args = {}, context = nil)
    name = name.to_sym
    tool = get_tool(name)

    unless tool
      raise ArgumentError, "Tool '#{name}' not found in registry"
    end

    implementation = tool[:implementation]

    case implementation
    when Proc
      # Execute the proc with the provided arguments and context
      if context
        context.instance_exec(args, &implementation)
      else
        implementation.call(args)
      end
    when Class
      # Create an instance of the tool class and execute it
      if implementation < BaseTool
        tool_instance = implementation.new
        tool_instance.execute(name, args, context)
      else
        raise ArgumentError, "Tool implementation class must inherit from BaseTool"
      end
    else
      raise ArgumentError, "Invalid tool implementation for '#{name}'"
    end
  end
end
