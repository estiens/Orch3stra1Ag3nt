# frozen_string_literal: true

# Service for managing vector embeddings and RAG functionality
class EmbeddingService
  attr_reader :llm, :collection, :task, :project

  # Initialize the embedding service
  # @param collection [String] The collection name to use for embeddings
  # @param task [Task] Optional task to associate with embeddings
  # @param project [Project] Optional project to associate with embeddings
  # @param llm [Langchain::LLM] Optional LLM to use (defaults to OpenRouter)
  def initialize(collection: "default", task: nil, project: nil, llm: nil)
    @collection = collection
    @task = task
    @project = project || (task&.project if task)
    @llm = llm || default_llm

    # Create schema if it doesn't exist
    ensure_schema_exists
  end

  # Ensure the vector search schema exists
  def ensure_schema_exists
    EmbeddingTool.create_default_schema(collection: @collection)
  rescue StandardError => e
    Rails.logger.error("Error creating schema: #{e.message}")
  end

  # Add text to the vector database
  # @param text [String] The text to embed
  # @param content_type [String] The type of content
  # @param source_url [String] Optional source URL
  # @param source_title [String] Optional source title
  # @param metadata [Hash] Additional metadata
  # @return [Object] The created embedding
  def add_text(text, content_type: "text", source_url: nil, source_title: nil, metadata: {})
    EmbeddingTool.store(
      content: text,
      content_type: content_type,
      collection: @collection,
      task: @task,
      project: @project,
      source_url: source_url,
      source_title: source_title,
      metadata: metadata
    )
  end

  # Add multiple texts to the vector database
  # @param texts [Array<String>] Array of texts to embed
  # @param content_type [String] The type of content
  # @param metadata [Hash] Additional metadata
  # @return [Array] The created embeddings
  def add_texts(texts, content_type: "text", metadata: {})
    # Add task and project IDs to metadata if present
    full_metadata = metadata.dup
    full_metadata[:task_id] = @task.id if @task.present?
    full_metadata[:project_id] = @project.id if @project.present?
    full_metadata[:content_type] = content_type

    EmbeddingTool.add_texts(
      texts: texts,
      content_type: content_type,
      collection: @collection,
      metadata: full_metadata
    )
  end

  # Add a document to the vector database with chunking
  # @param text [String] The document text to embed
  # @param chunk_size [Integer] Size of each chunk
  # @param chunk_overlap [Integer] Overlap between chunks
  # @param content_type [String] The type of content
  # @param source_url [String] Optional source URL
  # @param source_title [String] Optional source title
  # @param metadata [Hash] Additional metadata
  # @return [Array] The created embeddings
  def add_document(text, chunk_size: 1000, chunk_overlap: 200, content_type: "document",
                  source_url: nil, source_title: nil, metadata: {})
    EmbeddingTool.store_document(
      content: text,
      chunk_size: chunk_size,
      chunk_overlap: chunk_overlap,
      content_type: content_type,
      collection: @collection,
      task: @task,
      project: @project,
      source_url: source_url,
      source_title: source_title,
      metadata: metadata
    )
  end

  # Add data from files to the vector database
  # @param paths [Array<String>] Array of file paths to embed
  # @param metadata [Hash] Additional metadata
  # @return [Array] The created embeddings
  def add_data(paths, metadata: {})
    # Use langchainrb's add_data method for supported file formats
    client = EmbeddingTool.client(collection: @collection)

    # Add task and project IDs to metadata if present
    full_metadata = metadata.dup
    full_metadata[:task_id] = @task.id if @task.present?
    full_metadata[:project_id] = @project.id if @project.present?

    # Use langchainrb's add_data method
    client.add_data(paths: paths, metadata: full_metadata)
  end

  # Perform similarity search
  # @param query [String] The query text
  # @param k [Integer] Number of results to return
  # @param distance [String] Distance metric ("cosine", "euclidean", "inner_product")
  # @return [Array] Similar embeddings
  def similarity_search(query, k: 5, distance: "cosine")
    EmbeddingTool.search(
      text: query,
      limit: k,
      collection: @collection,
      task_id: @task&.id,
      project_id: @project&.id,
      distance: distance
    )
  end

  # Perform similarity search with HyDE (Hypothetical Document Embeddings)
  # @param query [String] The query text
  # @param k [Integer] Number of results to return
  # @return [Array] Similar embeddings
  def similarity_search_with_hyde(query, k: 5)
    EmbeddingTool.similarity_search_with_hyde(
      query: query,
      limit: k,
      collection: @collection,
      task_id: @task&.id,
      project_id: @project&.id
    )
  end

  # Perform similarity search by vector
  # @param embedding [Array<Float>] The embedding vector
  # @param k [Integer] Number of results to return
  # @return [Array] Similar embeddings
  def similarity_search_by_vector(embedding, k: 5)
    EmbeddingTool.similarity_search_by_vector(
      embedding: embedding,
      limit: k,
      collection: @collection,
      task_id: @task&.id,
      project_id: @project&.id
    )
  end

  # Perform RAG-based question answering
  # @param question [String] The question to answer
  # @param k [Integer] Number of documents to retrieve
  # @return [Hash] The answer and sources
  def ask(question, k: 5)
    EmbeddingTool.ask(
      question: question,
      limit: k,
      collection: @collection,
      task_id: @task&.id,
      project_id: @project&.id
    )
  end

  private

  # Parse a file and return its content and type
  def parse_file(path)
    extension = File.extname(path).downcase

    # Handle different file types
    case extension
    when ".txt", ".md"
      [ File.read(path), "text" ]
    when ".pdf"
      [ extract_pdf_text(path), "pdf" ]
    when ".docx"
      [ extract_docx_text(path), "docx" ]
    when ".html", ".htm"
      [ extract_html_text(path), "html" ]
    when ".csv"
      [ File.read(path), "csv" ]
    when ".json"
      [ File.read(path), "json" ]
    else
      # Default to plain text for unknown types
      [ File.read(path), "unknown" ]
    end
  rescue => e
    Rails.logger.error("Error parsing file #{path}: #{e.message}")
    [ "Error parsing file: #{e.message}", "error" ]
  end

  # Extract text from PDF
  def extract_pdf_text(path)
    # This would normally use a PDF parsing gem
    # For now, just return a placeholder
    "PDF text extraction would happen here for: #{path}"
  end

  # Extract text from DOCX
  def extract_docx_text(path)
    # This would normally use a DOCX parsing gem
    # For now, just return a placeholder
    "DOCX text extraction would happen here for: #{path}"
  end

  # Extract text from HTML
  def extract_html_text(path)
    require "nokogiri"
    html = Nokogiri::HTML(File.read(path))
    html.css("script, style").remove
    html.text.strip
  end

  # Default LLM
  def default_llm
    Langchain::LLM::OpenRouter.new(
      api_key: ENV["OPEN_ROUTER_API_KEY"],
      default_options: { chat_model: "openai/gpt-3.5-turbo" }
    )
  end
end
