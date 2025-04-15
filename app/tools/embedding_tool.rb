# frozen_string_literal: true

# Tool for generating embeddings and performing vector search using LangchainRB
class EmbeddingTool
  # Initialize the pgvector client
  def self.client(collection: "default")
    # Configure the pgvector client with database connection
    @client ||= Langchain::Vectorsearch::Pgvector.new(
      connection_string: ENV["DATABASE_URL"],
      schema_name: "vector_search",
      table_name: collection
    )
  end

  # Generate embedding for text
  def self.generate_embedding(text, model: "text-embedding-ada-002")
    # Get the embedding from the pgvector client
    client.embedding.embed_query(text)
  end

  # Create the default schema
  def self.create_default_schema(collection: "default")
    client(collection: collection).create_default_schema
  end

  # Store content with its embedding
  def self.store(content:, content_type: "text", collection: "default",
                task: nil, project: nil, source_url: nil, source_title: nil, metadata: {})
    # Resolve project from task if not provided directly
    if project.nil? && task.present? && task.project.present?
      project = task.project
    end

    # Prepare metadata
    full_metadata = {
      content_type: content_type,
      source_url: source_url,
      source_title: source_title
    }

    # Add task and project IDs if present
    full_metadata[:task_id] = task.id if task.present?
    full_metadata[:project_id] = project.id if project.present?

    # Merge with additional metadata
    full_metadata.merge!(metadata) if metadata.present?

    # Add text using langchainrb's pgvector
    result = client(collection: collection).add_texts(
      texts: [ content ],
      metadatas: [ full_metadata ]
    )

    # Return the first created embedding
    result.first
  end

  # Add multiple texts
  def self.add_texts(texts:, content_type: "text", collection: "default", metadata: {})
    # Prepare metadata for each text
    metadatas = texts.map do |_|
      { content_type: content_type }.merge(metadata)
    end

    # Add texts using langchainrb's pgvector
    client(collection: collection).add_texts(
      texts: texts,
      metadatas: metadatas
    )
  end

  # Search for similar content
  def self.search(text:, limit: 5, collection: "default", task_id: nil, project_id: nil, distance: "cosine")
    # Set up filter based on task_id and project_id
    filter = {}
    filter[:task_id] = task_id if task_id.present?
    filter[:project_id] = project_id if project_id.present?

    # Search using langchainrb's pgvector
    client(collection: collection).similarity_search(
      query: text,
      k: limit,
      filter: filter.presence
    )
  end

  # Store a document with chunking for better retrieval
  def self.store_document(content:, chunk_size: 1000, chunk_overlap: 200, **options)
    return [] if content.blank?

    # Split content into chunks
    chunks = chunk_text(content, chunk_size, chunk_overlap)

    # Store each chunk with its embedding
    chunks.map do |chunk|
      store(content: chunk, **options)
    end
  end

  # Create a RAG system for question answering
  def self.ask(question:, limit: 5, collection: "default", task_id: nil, project_id: nil)
    # Set up filter based on task_id and project_id
    filter = {}
    filter[:task_id] = task_id if task_id.present?
    filter[:project_id] = project_id if project_id.present?

    # Use langchainrb's pgvector ask method
    result = client(collection: collection).ask(
      question: question,
      filter: filter.presence
    )

    # Format the response
    {
      answer: result.answer,
      sources: result.source_documents.map do |doc|
        {
          content: doc.page_content.truncate(100),
          url: doc.metadata[:source_url],
          title: doc.metadata[:source_title]
        }
      end
    }
  end

  # Search by vector embedding
  def self.similarity_search_by_vector(embedding:, limit: 5, collection: "default", task_id: nil, project_id: nil)
    # Set up filter based on task_id and project_id
    filter = {}
    filter[:task_id] = task_id if task_id.present?
    filter[:project_id] = project_id if project_id.present?

    # Search using langchainrb's pgvector by vector
    client(collection: collection).similarity_search_by_vector(
      embedding: embedding,
      k: limit,
      filter: filter.presence
    )
  end

  # Similarity search with HyDE
  def self.similarity_search_with_hyde(query:, limit: 5, collection: "default", task_id: nil, project_id: nil)
    # Set up filter based on task_id and project_id
    filter = {}
    filter[:task_id] = task_id if task_id.present?
    filter[:project_id] = project_id if project_id.present?

    # Use langchainrb's pgvector similarity_search_with_hyde method
    client(collection: collection).similarity_search_with_hyde(
      query: query,
      k: limit,
      filter: filter.presence
    )
  end

  private

  # Helper method to chunk text
  def self.chunk_text(text, chunk_size, chunk_overlap)
    return [ text ] if text.length <= chunk_size

    chunks = []
    start_idx = 0

    while start_idx < text.length
      end_idx = [ start_idx + chunk_size, text.length ].min

      # Try to find a good breaking point (period, newline, space)
      if end_idx < text.length
        [ "\n\n", "\n", ". ", " " ].each do |separator|
          separator_idx = text[start_idx...end_idx].rindex(separator)
          if separator_idx
            end_idx = start_idx + separator_idx + separator.length
            break
          end
        end
      end

      chunks << text[start_idx...end_idx]
      start_idx = [ end_idx - chunk_overlap, start_idx + 1 ].max
    end

    chunks
  end
end
