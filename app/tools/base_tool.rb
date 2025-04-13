# Base class for all tools in the system
class BaseTool
  attr_reader :name, :description
  
  def initialize(name, description)
    @name = name
    @description = description
  end
  
  # This method should be implemented by subclasses
  def call(*args)
    raise NotImplementedError, "Subclasses must implement #call"
  end
  
  # Convert to a Langchain tool
  def to_langchain_tool
    Langchain::Tool.new(
      name: name.to_s,
      description: description,
      function: ->(args) { call(args) }
    )
  end
end
