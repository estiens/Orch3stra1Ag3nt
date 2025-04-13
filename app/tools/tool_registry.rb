# Tool Registry for managing and accessing all available tools
class ToolRegistry
  class << self
    def register(tool_class)
      tools[tool_class.name.underscore] = tool_class
    end
    
    def get(tool_name)
      tool_class = tools[tool_name.to_s]
      tool_class&.new
    end
    
    def all
      tools.values.map(&:new)
    end
    
    def to_langchain_tools
      all.map(&:to_langchain_tool)
    end
    
    private
    
    def tools
      @tools ||= {}
    end
  end
end

# Register all tools
Rails.configuration.to_prepare do
  [
    CodeTool,
    PerplexitySearchTool,
    ResearchTool,
    SerpApiSearchTool,
    VectorEmbeddingTool,
    WebScraperTool
  ].each do |tool_class|
    ToolRegistry.register(tool_class)
  end
end
