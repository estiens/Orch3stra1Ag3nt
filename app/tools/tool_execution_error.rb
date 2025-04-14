class ToolExecutionError < StandardError
  attr_reader :tool_name, :original_exception

  def initialize(message, tool_name: nil, original_exception: nil)
    @tool_name = tool_name
    @original_exception = original_exception
    full_message = tool_name ? "Error executing tool '#{tool_name}': #{message}" : message
    super(full_message)
  end
end
