# frozen_string_literal: true

# LangchainRB tool definition for the embedding tool
class LangchainEmbeddingTool
  extend Langchain::ToolDefinition

  # Define schema for adding a single text
  define_function :add_text, description: "Add a single text to the vector database" do
    property :text, type: "string", description: "The text to embed", required: true
    property :content_type, type: "string", description: "The type of content", required: false
    property :collection, type: "string", description: "The collection to add to", required: false
    property :source_url, type: "string", description: "Source URL of the content", required: false
    property :source_title, type: "string", description: "Title of the source", required: false
    property :metadata, type: "object", description: "Additional metadata", required: false
  end

  # Define schema for adding multiple texts
  define_function :add_texts, description: "Add multiple texts to the vector database" do
    property :texts, type: "array", description: "Array of texts to embed", required: true
    property :content_type, type: "string", description: "The type of content", required: false
    property :collection, type: "string", description: "The collection to add to", required: false
    property :metadata, type: "object", description: "Additional metadata", required: false
  end

  # Define schema for adding a document
  define_function :add_document, description: "Add a document to the vector database with chunking" do
    property :text, type: "string", description: "The document text to embed", required: true
    property :chunk_size, type: "integer", description: "Size of each chunk", required: false
    property :chunk_overlap, type: "integer", description: "Overlap between chunks", required: false
    property :content_type, type: "string", description: "The type of content", required: false
    property :collection, type: "string", description: "The collection to add to", required: false
    property :source_url, type: "string", description: "Source URL of the content", required: false
    property :source_title, type: "string", description: "Title of the source", required: false
    property :metadata, type: "object", description: "Additional metadata", required: false
  end

  # Define schema for similarity search
  define_function :similarity_search, description: "Search for similar content in the vector database" do
    property :query, type: "string", description: "The query text", required: true
    property :limit, type: "integer", description: "Maximum number of results", required: false
    property :collection, type: "string", description: "The collection to search", required: false
    property :distance, type: "string", description: "Distance metric (cosine, euclidean, inner_product)", required: false
  end

  # Define schema for RAG-based question answering
  define_function :ask, description: "Answer a question using RAG (Retrieval Augmented Generation)" do
    property :question, type: "string", description: "The question to answer", required: true
    property :limit, type: "integer", description: "Number of documents to retrieve", required: false
    property :collection, type: "string", description: "The collection to search", required: false
  end

  def initialize
    # No initialization needed
  end

  # Add a single text
  def add_text(text:, content_type: "text", collection: "default", source_url: nil, source_title: nil, metadata: {})
    service = EmbeddingService.new(collection: collection)
    embedding = service.add_text(
      text,
      content_type: content_type,
      source_url: source_url,
      source_title: source_title,
      metadata: metadata
    )

    {
      status: "success",
      message: "Text added to vector database",
      embedding_id: embedding&.id || "unknown"
    }
  end

  # Add multiple texts
  def add_texts(texts:, content_type: "text", collection: "default", metadata: {})
    service = EmbeddingService.new(collection: collection)
    embeddings = service.add_texts(
      texts,
      content_type: content_type,
      metadata: metadata
    )

    {
      status: "success",
      message: "#{embeddings.count} texts added to vector database",
      embedding_count: embeddings.count
    }
  end

  # Add a document
  def add_document(text:, chunk_size: 1000, chunk_overlap: 200, content_type: "document",
                  collection: "default", source_url: nil, source_title: nil, metadata: {})
    service = EmbeddingService.new(collection: collection)
    embeddings = service.add_document(
      text,
      chunk_size: chunk_size,
      chunk_overlap: chunk_overlap,
      content_type: content_type,
      source_url: source_url,
      source_title: source_title,
      metadata: metadata
    )

    {
      status: "success",
      message: "Document added to vector database with #{embeddings.count} chunks",
      chunk_count: embeddings.count
    }
  end

  # Similarity search
  def similarity_search(query:, limit: 5, collection: "default", distance: "cosine")
    service = EmbeddingService.new(collection: collection)
    results = service.similarity_search(query, k: limit, distance: distance)

    {
      status: "success",
      message: "Found #{results.count} similar documents",
      results: results.map do |result|
        {
          id: result.respond_to?(:id) ? result.id : nil,
          content: result.respond_to?(:page_content) ? result.page_content.to_s.truncate(200) :
                  (result.respond_to?(:content) ? result.content.to_s.truncate(200) : "Unknown content"),
          content_type: result.respond_to?(:metadata) ? result.metadata[:content_type] :
                       (result.respond_to?(:content_type) ? result.content_type : "unknown"),
          source_url: result.respond_to?(:metadata) ? result.metadata[:source_url] :
                     (result.respond_to?(:source_url) ? result.source_url : nil),
          source_title: result.respond_to?(:metadata) ? result.metadata[:source_title] :
                       (result.respond_to?(:source_title) ? result.source_title : nil),
          metadata: result.respond_to?(:metadata) ? result.metadata :
                   (result.respond_to?(:metadata) ? result.metadata : {})
        }
      end
    }
  end

  # Similarity search with HyDE
  def similarity_search_with_hyde(query:, limit: 5, collection: "default")
    service = EmbeddingService.new(collection: collection)
    results = service.similarity_search_with_hyde(query, k: limit)

    {
      status: "success",
      message: "Found #{results.count} similar documents using HyDE",
      results: results.map do |result|
        {
          content: result.respond_to?(:page_content) ? result.page_content.to_s.truncate(200) :
                  (result.respond_to?(:content) ? result.content.to_s.truncate(200) : "Unknown content"),
          metadata: result.respond_to?(:metadata) ? result.metadata : {}
        }
      end
    }
  end

  # RAG-based question answering
  def ask(question:, limit: 5, collection: "default")
    service = EmbeddingService.new(collection: collection)
    result = service.ask(question, k: limit)

    {
      status: "success",
      answer: result[:answer],
      sources: result[:sources].map do |source|
        {
          content: source[:content],
          url: source[:url],
          title: source[:title]
        }
      end
    }
  end
end
