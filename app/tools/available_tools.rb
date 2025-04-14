class AvailableTools
    def self.list
      [
        PerplexitySearchTool,
        ResearchTool,
        SerpApiSearchTool,
        VectorEmbeddingTool,
        Langchain::Tool::Calculator,
        Langchain::Tool::Database,
        Langchain::Tool::FileSystem,
        Langchain::Tool::RubyCodeInterpreter,
        Langchain::Tool::NewsRetriever,
        Langchain::Tool::Tavily,
        Langchain::Tool::Weather,
        Langchain::Tool::Wikipedia
      ]
    end
end
