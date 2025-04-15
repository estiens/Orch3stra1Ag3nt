# frozen_string_literal: true
require 'concurrent'

# Service for managing vector embeddings and RAG functionality
class EmbeddingService
  attr_reader :collection, :task, :project, :api_client, :text_chunker, :vector_store
  
  # Constants for embedding configuration
  EMBEDDING_MODEL = "gte-large-buc"
  EMBEDDING_DIMENSIONS = 1024
  
  def initialize(collection: nil, task: nil, project: nil)
    @task = task
    @project = project || task&.project
    @collection = collection || (@project ? "Project#{@project.id}" : "default")
    
    # Initialize component services
    @api_client = Embedding::ApiClient.new
    @text_chunker = Embedding::TextChunker.new
    @vector_store = Embedding::VectorStore.new(
      collection: @collection,
      task: @task,
      project: @project
    )
  end

  def add_text(text, content_type: "text", source_url: nil, source_title: nil, metadata: {}, force: false)
    return if !force && @vector_store.embedding_exists?(text, content_type: content_type)
    
    # Generate embedding
    start_time = Time.now
    embedding = generate_embedding(text)
    generation_time = Time.now - start_time
    
    if embedding.nil? || embedding.empty?
      Rails.logger.error("Embedding generation failed for content: #{text.truncate(100)}")
      raise "Embedding generation failed"
    end
    
    Rails.logger.info("Generated embedding in #{generation_time.round(2)}s (#{embedding.size} dimensions)")
    
    # Store in database
    @vector_store.store(
      content: text,
      embedding: embedding,
      content_type: content_type,
      source_url: source_url,
      source_title: source_title,
      metadata: metadata
    )
  end

  # Add multiple texts; skips existing if not forced
  def add_texts(texts, content_type: "text", metadata: {}, force: false)
    texts.uniq.map do |text|
      add_text(text, content_type: content_type, metadata: metadata, force: force)
    end.compact
  end

  # Process a document by chunking it and storing the chunks with embeddings
  def add_document(text, chunk_size: 512, chunk_overlap: 25, content_type: "document", 
                  source_url: nil, source_title: nil, metadata: {}, force: false)
    Rails.logger.debug("EmbeddingService: Starting add_document (#{text.bytesize} bytes)")
    return [] if text.blank?

    # Generate chunks using optimized parallel processing
    chunk_start = Time.now
    Rails.logger.debug("EmbeddingService: Starting chunking of text")
    chunks = @text_chunker.chunk_text(text, chunk_size, chunk_overlap)
    chunk_time = Time.now - chunk_start
    Rails.logger.debug("EmbeddingService: Chunking completed in #{chunk_time.round(2)}s - created #{chunks.size} chunks")
    return [] if chunks.empty?

    # Filter out existing chunks if not forced - use a more efficient approach
    filter_start = Time.now
    chunks_to_process = if force
      Rails.logger.debug("EmbeddingService: Forced processing - skipping duplicate check")
      chunks
    else
      # Use a more efficient query approach with batching for large chunk sets
      Rails.logger.debug("EmbeddingService: Checking for existing chunks")
      remaining = @vector_store.filter_existing_chunks(chunks)
      Rails.logger.debug("EmbeddingService: Will process #{remaining.size} new chunks")
      remaining
    end
    filter_time = Time.now - filter_start
    Rails.logger.debug("EmbeddingService: Duplicate filtering completed in #{filter_time.round(2)}s")

    return [] if chunks_to_process.empty?

    # Process chunks in batches
    Rails.logger.debug("EmbeddingService: Starting batch processing of #{chunks_to_process.size} chunks")
    process_chunks_in_batches(
      chunks_to_process,
      text,
      chunk_size,
      chunk_overlap,
      content_type,
      source_url,
      source_title,
      metadata
    )
  end

  # Remove all embeddings in collection
  def delete_all_embeddings_in_collection
    @vector_store.delete_all_embeddings_in_collection
  end

  # DANGEROUS: Truncate whole table!
  def truncate_embeddings
    @vector_store.truncate_embeddings
  end

  # Main RAG ask function
  def ask(question, k: 5)
    similar_docs = similarity_search(question, k: k)
    prompt = "Answer the question based on the following documents:\n\n#{similar_docs.map(&:content).join("\n\n")}\n\nQuestion: #{question}"
    response = llm.chat(messages: [{ role: "user", content: prompt }])
    response.chat_completion
  end

  # Similarity search by input string
  def similarity_search(query, k: 5, distance: "cosine")
    query_embedding = generate_embedding(query)
    similarity_search_by_vector(query_embedding, k: k, distance: distance)
  end

  # Similarity search by vector
  def similarity_search_by_vector(embedding, k: 5, distance: "cosine")
    @vector_store.similarity_search_by_vector(embedding, k: k, distance: distance)
  end

  # Generate embedding for a text
  def generate_embedding(text)
    embedding = @api_client.generate_embedding(text)
    
    # Ensure we have the right dimensions
    normalize_embedding_dimensions(embedding)
  end

  # --------------------------
  # Private helpers and logic
  # --------------------------
  private

  # Process chunks in batches for better performance
  def process_chunks_in_batches(chunks_to_process, original_text, chunk_size, chunk_overlap, 
                               content_type, source_url, source_title, metadata)
    all_results = []
    total_saved = 0

    # Buffers for accumulating chunks before DB commit
    pending_chunks = []
    pending_embeddings = []
    
    # Constants for batch processing
    api_batch_size = Embedding::ApiClient::API_BATCH_SIZE
    db_commit_frequency = Embedding::VectorStore::DB_COMMIT_FREQUENCY

    # Process in small batches for API calls
    chunks_to_process.each_slice(api_batch_size).with_index do |api_batch, api_batch_idx|
      api_batch_num = api_batch_idx + 1
      api_batch_total = (chunks_to_process.size.to_f / api_batch_size).ceil
      
      Rails.logger.debug("EmbeddingService: Processing API batch #{api_batch_num}/#{api_batch_total} (#{api_batch.size} chunks)")
      
      begin
        # Generate embeddings for this API batch
        api_start = Time.now
        Rails.logger.debug("EmbeddingService: Starting API call for batch #{api_batch_num}")
        batch_embeddings = @api_client.generate_batch_embeddings(api_batch)
        api_time = Time.now - api_start
        Rails.logger.debug("EmbeddingService: API call completed in #{api_time.round(2)}s - received #{batch_embeddings.compact.size} embeddings")

        # Add to pending buffers
        pending_chunks.concat(api_batch)
        pending_embeddings.concat(batch_embeddings)

        # If we've reached commit frequency or this is the last batch, commit to database
        if (api_batch_num % db_commit_frequency == 0) || 
            (api_batch_idx == (chunks_to_process.size.to_f / api_batch_size).ceil - 1)
          
          db_start = Time.now
          Rails.logger.debug("EmbeddingService: Starting database commit for #{pending_chunks.size} chunks")
          
          @vector_store.commit_batch_to_database(
            pending_chunks, 
            pending_embeddings, 
            original_text, 
            chunk_size, 
            chunk_overlap, 
            content_type, 
            source_url, 
            source_title, 
            metadata,
            chunks_to_process.size
          ).tap do |new_records|
            all_results.concat(new_records)
            total_saved += new_records.count
          end
          
          db_time = Time.now - db_start
          Rails.logger.debug("EmbeddingService: Database commit completed in #{db_time.round(2)}s - saved #{total_saved} records")

          # Clear buffers after commit
          pending_chunks = []
          pending_embeddings = []
        end
      rescue => e
        Rails.logger.error("EmbeddingService: Error in API batch #{api_batch_num}: #{e.message}\n#{e.backtrace.join("\n")}")
        # Continue with next batch
      end
    end

    Rails.logger.debug("EmbeddingService: Batch processing completed - processed #{chunks_to_process.size} chunks, saved #{all_results.size} records")
    all_results
  end

  # Normalize embedding dimensions to ensure consistent size
  def normalize_embedding_dimensions(embedding)
    # Ensure we have the right dimensions
    if embedding.size != EMBEDDING_DIMENSIONS
      if embedding.size < EMBEDDING_DIMENSIONS
        embedding = embedding + Array.new(EMBEDDING_DIMENSIONS - embedding.size, 0.0)
      else
        embedding = embedding[0...EMBEDDING_DIMENSIONS]
      end
    end
    embedding
  end

  # LLM provider - lazily initialized
  def llm
    @llm ||= Langchain::LLM::OpenRouter.new(
      api_key: ENV["OPEN_ROUTER_API_KEY"],
      default_options: {
        chat_model: Rails.configuration.llm[:models][:fast],
        temperature: 0.2
      }
    )
  end
end
