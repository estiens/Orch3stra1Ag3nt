class AvailableTools
    def self.list
      tools = [
        PerplexitySearchTool,
        ResearchTool
      ]

      # Add Langchain built-in tools
      tools += [
        Langchain::Tool::Calculator,
        Langchain::Tool::Database,
        Langchain::Tool::FileSystem,
        Langchain::Tool::RubyCodeInterpreter,
        Langchain::Tool::NewsRetriever,
        Langchain::Tool::Tavily,
        Langchain::Tool::Weather,
        Langchain::Tool::Wikipedia
      ] if defined?(Langchain::Tool)

      tools
    end
end
