# frozen_string_literal: true

class EmbeddingTool
  extend Langchain::ToolDefinition

  # Constants for default values
  DEFAULT_COLLECTION = "default"
  DEFAULT_CONTENT_TYPE = "text"
  DEFAULT_LIMIT = 5
  DEFAULT_DISTANCE = "euclidean"
  DEFAULT_CHUNK_SIZE = 500
  DEFAULT_CHUNK_OVERLAP = 25
  MAX_CHUNK_SIZE = 5000
  MAX_CONTENT_PREVIEW = 200

  # Unified data addition: accepts a String or Array, and can do chunking if requested
  define_function :add, description: "Add one or more texts/documents to the vector database; can also chunk a large document" do
    property :texts, type: "array", description: "Array of texts to embed. For a single text, just provide one item.", required: true
    property :content_type, type: "string", description: "The type of content", required: false
    property :collection, type: "string", description: "The collection to add to", required: false
    property :chunk_size, type: "integer", description: "Chunk large texts into segments of this size (optional)", required: false
    property :chunk_overlap, type: "integer", description: "Chunk overlap when chunking (optional)", required: false
    property :source_url, type: "string", description: "Source URL of the content", required: false
    property :source_title, type: "string", description: "Title of the source", required: false
    property :metadata, type: "object", description: "Additional metadata", required: false
  end

  # Unified similarity search (optionally allows hyde or other modes)
  define_function :similarity_search, description: "Search for similar content (semantic vector search) in the vector database" do
    property :query, type: "string", description: "The query text", required: true
    property :limit, type: "integer", description: "Maximum number of results", required: false
    property :collection, type: "string", description: "The collection to search", required: false
    property :distance, type: "string", description: "Distance metric (cosine, euclidean, inner_product)", required: false
    property :mode, type: "string", description: "Optional search mode (e.g., 'hyde' for HyDE retrieval)", required: false
  end

  # RAG QA (optional: just wraps a similarity search and LLM answer)
  define_function :ask, description: "Answer a question using RAG (Retrieval Augmented Generation)" do
    property :question, type: "string", description: "The question to answer", required: true
    property :limit, type: "integer", description: "Number of documents to retrieve", required: false
    property :collection, type: "string", description: "The collection to search", required: false
  end

  # LLM provider - lazy-initialized
  def llm
    @llm ||= Langchain::LLM::OpenRouter.new(
      api_key: ENV["OPEN_ROUTER_API_KEY"],
      default_options: {
        chat_model: Rails.configuration.llm[:models][:fast],
        temperature: 0.2
      }
    )
  end

  # Add files to the vector database
  def add_files(
    files:,
    content_type: DEFAULT_CONTENT_TYPE,
    collection: DEFAULT_COLLECTION,
    chunk_size: DEFAULT_CHUNK_SIZE,
    chunk_overlap: DEFAULT_CHUNK_OVERLAP,
    source_url: nil,
    source_title: nil,
    metadata: {}
  )
    # Validate parameters
    validate_chunking_params(chunk_size, chunk_overlap)

    # Initialize service and normalize input
    service = EmbeddingService.new(collection: collection)
    files_array = to_array(files)
    raise ArgumentError, "You must supply at least one file." if files_array.empty?

    # Process each file
    added = []
    files_array.each do |file|
      file_obj = validate_and_open_file(file)

      # Prepare file-specific metadata
      file_metadata = build_file_metadata(file_obj, merge: metadata, content_type: content_type, source_url: source_url, source_title: source_title)
      # Add document to embedding service
      result = service.add_document(
        file_obj.read,
        chunk_size: chunk_size,
        chunk_overlap: chunk_overlap,
        content_type: content_type,
        metadata: file_metadata
      )

      added << {
        path: file_obj.path,
        size: file_obj.size,
        chunk_preview: result.first&.content&.first(40),
        chunks: result.count
      }
    end

    {
      status: "success",
      message: "Files added successfully",
      added: added,
      total_count: added.count
    }
  end

  # Add text(s) to the vector database
  def add(
    texts:,
    content_type: DEFAULT_CONTENT_TYPE,
    collection: DEFAULT_COLLECTION,
    chunk_size: nil,
    chunk_overlap: nil,
    source_url: nil,
    source_title: nil,
    metadata: {}
  )
    # Validate chunking parameters if provided
    validate_chunking_params(chunk_size, chunk_overlap) if chunk_size

    # Initialize service and normalize input
    service = EmbeddingService.new(collection: collection)
    items = to_array(texts)
    raise ArgumentError, "You must supply at least one text." if items.empty?

    # Process each text
    added = []
    items.each do |text|
      # Prepare metadata
      text_metadata = build_metadata(
        content_type: content_type,
        source_url: source_url,
        source_title: source_title,
        extra: metadata
      )

      # If chunking is requested, delegate to the chunk-aware method
      if chunk_size
        embeddings = service.add_document(
          text,
          chunk_size: chunk_size,
          chunk_overlap: chunk_overlap || 0,
          content_type: content_type,
          source_url: source_url,
          source_title: source_title,
          metadata: text_metadata
        )
        added << {
          status: "success",
          message: "Document added with #{embeddings.count} chunks",
          chunk_count: embeddings.count
        }
      else
        embedding = service.add_text(
          text,
          content_type: content_type,
          source_url: source_url,
          source_title: source_title,
          metadata: text_metadata
        )
        added << {
          status: "success",
          message: "Text added",
          embedding_id: embedding&.id || "unknown"
        }
      end
    end

    {
      status: "success",
      added: added,
      total_count: added.map { |item| item[:chunk_count] || 1 }.sum
    }
  end

  # Unified similarity search
  def similarity_search(
    query:,
    limit: DEFAULT_LIMIT,
    collection: DEFAULT_COLLECTION,
    distance: DEFAULT_DISTANCE,
    mode: nil
  )
    Rails.logger.tagged("EmbeddingTool", "similarity_search") do
      service = EmbeddingService.new(collection: collection)
      results = service.similarity_search(query, k: limit, distance: distance)

      {
        status: "success",
        message: "Found #{results.count} similar documents",
        results: Array(results).map { |result| format_search_result(result) }
      }
    end
  end

  # RAG-based QA (wraps embedding service's ask)
  def ask(question:, limit: DEFAULT_LIMIT, collection: DEFAULT_COLLECTION)
    Rails.logger.tagged("EmbeddingTool", "ask") do
      similar = similarity_search(query: question, limit: limit, collection: collection)

      # Extract content from results for the prompt
      contents = similar[:results].map { |r| r[:content] }.join("\n\n")

      prompt = "Answer the question based on the following documents:\n\n#{contents}\n\nQuestion: #{question}"
      response = llm.chat(messages: [ { role: "user", content: prompt } ])
      answer = response.chat_completion

      # Log the LLM call if there's a method for it
      log_llm_call(question, response) if respond_to?(:log_llm_call, true)

      {
        status: "success",
        answer: answer,
        sources: similar[:results].map do |result|
          {
            content: result[:content],
            url: result[:source_url],
            title: result[:source_title]
          }
        end
      }
    end
  end

  private

  # Convert input to array, handling both single items and arrays
  def to_array(input)
    Array(input).compact
  end

  # Validate chunking parameters
  def validate_chunking_params(chunk_size, chunk_overlap)
    return unless chunk_size

    raise ArgumentError, "Chunk size must be greater than 0." if chunk_size <= 0
    raise ArgumentError, "Chunk overlap must be greater than or equal to 0." if chunk_overlap && chunk_overlap < 0
    raise ArgumentError, "Chunk size must be greater than chunk overlap." if chunk_overlap && chunk_size <= chunk_overlap
    raise ArgumentError, "Chunk size must be less than or equal to #{MAX_CHUNK_SIZE}" if chunk_size > MAX_CHUNK_SIZE
  end

  # Validate and open a file
  def validate_and_open_file(file)
    if file.is_a?(String)
      raise ArgumentError, "File not found: #{file}" unless File.exist?(file)
      raise ArgumentError, "File is not readable: #{file}" unless File.readable?(file)
      File.open(file)
    elsif file.respond_to?(:read)
      path = file.respond_to?(:path) ? file.path : nil
      if path
        raise ArgumentError, "File not found: #{path}" unless File.exist?(path)
        raise ArgumentError, "File is not readable: #{path}" unless File.readable?(path)
      end
      file
    else
      raise ArgumentError, "Unsupported file object: #{file.inspect}"
    end
  end

  private

# Generic metadata
def build_metadata(content_type: nil, source_url: nil, source_title: nil, extra: {})
  {
    content_type: content_type,
    source_url: source_url,
    source_title: source_title
  }.compact.merge(extra || {})
end

# File-specific metadata (for IO/File objects)
def build_file_metadata(file_obj, merge: {}, content_type: nil, source_url: nil, source_title: nil)
  metadata = {}
  metadata[:source_title]   = source_title if source_title
  metadata[:source_url]     = source_url if source_url
  if file_obj.respond_to?(:path)
    metadata[:source_title] ||= file_obj.path
    metadata[:file_name]      = File.basename(file_obj.path) rescue nil
    metadata[:file_ext]       = File.extname(file_obj.path) rescue nil
  end
  metadata[:file_size]        = file_obj.size if file_obj.respond_to?(:size)
  metadata[:content_type]     = content_type ||
    (file_obj.respond_to?(:content_type) && file_obj.content_type) ||
    DEFAULT_CONTENT_TYPE
  metadata.merge!(file_obj.metadata) if file_obj.respond_to?(:metadata)
  metadata.merge!(merge || {})
  metadata.compact
end


  # Format search result for consistent output
  def format_search_result(result)
    metadata = result.respond_to?(:metadata) ? result.metadata : {}
    {
      id: result.respond_to?(:id) ? result.id : nil,
      content: extract_content(result, metadata),
      content_type: metadata[:content_type] || result.try(:content_type) || "unknown",
      source_url: metadata[:source_url] || result.try(:source_url),
      source_title: metadata[:source_title] || result.try(:source_title),
      metadata: metadata
    }
  end

  # Extract content from various result types
  def extract_content(result, metadata = {})
    metadata[:content] ||
      (result.respond_to?(:page_content) && result.page_content.to_s.truncate(MAX_CONTENT_PREVIEW)) ||
      (result.respond_to?(:content) && result.content.to_s.truncate(MAX_CONTENT_PREVIEW)) ||
      "Unknown content"
  end

  # Log LLM calls
  def log_llm_call(question, response)
    Rails.logger.tagged("EmbeddingTool", "llm_call") do
      Rails.logger.info("LLM call for question: #{question}")
    end
  end
end
