# frozen_string_literal: true
require 'concurrent'

# frozen_string_literal: true
require 'concurrent'

# Service for managing vector embeddings and RAG functionality
class EmbeddingService
  attr_reader :collection, :task, :project
  
  # Constants for embedding configuration
  EMBEDDING_MODEL = "gte-large-buc"
  DEFAULT_API_ENDPOINT = "https://piujqyd9p0cdbgx1.us-east4.gcp.endpoints.huggingface.cloud"
  EMBEDDING_DIMENSIONS = 1024
  
  # Constants for batch processing
  API_BATCH_SIZE = 8
  DB_COMMIT_FREQUENCY = 10
  MAX_RETRIES = 3
  
  def initialize(collection: nil, task: nil, project: nil)
    @task = task
    @project = project || task&.project
    @collection = collection || (@project ? "Project#{@project.id}" : "default")
  end

  def add_text(text, content_type: "text", source_url: nil, source_title: nil, metadata: {}, force: false)
    return if !force && embedding_exists?(text, content_type: content_type)
    store(
      content: text,
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
    chunks = parallel_chunk_text(text, chunk_size, chunk_overlap)
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
      remaining = filter_existing_chunks(chunks)
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
  
  # More efficient filtering of existing chunks
  def filter_existing_chunks(chunks)
    return chunks if chunks.empty?
    
    # For large chunk sets, process in batches to avoid memory issues
    if chunks.size > 1000
      # Process in batches of 1000
      result = []
      chunks.each_slice(1000) do |batch|
        existing = VectorEmbedding.where(collection: @collection)
                                  .where(content: batch)
                                  .pluck(:content)
        result.concat(batch - existing)
      end
      return result
    else
      # For smaller sets, process all at once
      existing_chunks = VectorEmbedding.where(collection: @collection)
                                       .where(content: chunks)
                                       .pluck(:content)
      return chunks - existing_chunks
    end
  end

  # Remove all embeddings in collection
  def delete_all_embeddings_in_collection
    VectorEmbedding.where(collection: @collection).delete_all
  end

  # DANGEROUS: Truncate whole table!
  def truncate_embeddings
    ActiveRecord::Base.connection.execute("TRUNCATE TABLE vector_embeddings RESTART IDENTITY;")
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
    VectorEmbedding
      .where(collection: @collection)
      .nearest_neighbors(:embedding, embedding, distance: distance)
      .limit(k)
  end

  # Generate embedding for a text
  def generate_embedding(text)
    embedding = generate_huggingface_embedding(text)

    # Handle nested array format (API sometimes returns [[float, float, ...]])
    if embedding.is_a?(Array) && embedding.size == 1 && embedding.first.is_a?(Array)
      embedding = embedding.first
    end

    # Ensure we have the right dimensions
    normalize_embedding_dimensions(embedding)
  end

  # --------------------------
  # Private helpers and logic
  # --------------------------
  private

  def embedding_exists?(content, content_type: nil)
    conditions = { collection: @collection, content: content }
    conditions[:content_type] = content_type if content_type
    VectorEmbedding.exists?(conditions)
  end

  # Process chunks in batches for better performance
  def process_chunks_in_batches(chunks_to_process, original_text, chunk_size, chunk_overlap, 
                               content_type, source_url, source_title, metadata)
    all_results = []
    total_saved = 0

    # Buffers for accumulating chunks before DB commit
    pending_chunks = []
    pending_embeddings = []

    # Process in small batches for API calls
    chunks_to_process.each_slice(API_BATCH_SIZE).with_index do |api_batch, api_batch_idx|
      api_batch_num = api_batch_idx + 1
      api_batch_total = (chunks_to_process.size.to_f / API_BATCH_SIZE).ceil
      
      Rails.logger.debug("EmbeddingService: Processing API batch #{api_batch_num}/#{api_batch_total} (#{api_batch.size} chunks)")
      
      begin
        # Generate embeddings for this API batch
        api_start = Time.now
        Rails.logger.debug("EmbeddingService: Starting API call for batch #{api_batch_num}")
        batch_embeddings = generate_tei_embeddings(api_batch)
        api_time = Time.now - api_start
        Rails.logger.debug("EmbeddingService: API call completed in #{api_time.round(2)}s - received #{batch_embeddings.compact.size} embeddings")

        # Add to pending buffers
        pending_chunks.concat(api_batch)
        pending_embeddings.concat(batch_embeddings)

        # If we've reached commit frequency or this is the last batch, commit to database
        if (api_batch_num % DB_COMMIT_FREQUENCY == 0) || 
            (api_batch_idx == (chunks_to_process.size.to_f / API_BATCH_SIZE).ceil - 1)
          
          db_start = Time.now
          Rails.logger.debug("EmbeddingService: Starting database commit for #{pending_chunks.size} chunks")
          
          commit_batch_to_database(
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

  # Commit a batch of chunks and embeddings to the database
  def commit_batch_to_database(pending_chunks, pending_embeddings, original_text, chunk_size, 
                              chunk_overlap, content_type, source_url, source_title, metadata, total_chunks)
    return [] if pending_chunks.empty? || pending_embeddings.empty?

    # Prepare base metadata
    base_metadata = prepare_base_metadata(
      original_text, 
      chunk_size, 
      chunk_overlap, 
      content_type, 
      source_url, 
      source_title, 
      metadata
    )

    # Build records for bulk insert
    records = []
    pending_chunks.zip(pending_embeddings).each_with_index do |(chunk, embedding), chunk_idx|
      next if embedding.nil?

      # Add chunk-specific metadata
      chunk_metadata = base_metadata.dup
      chunk_metadata[:chunk_index] = chunk_idx
      chunk_metadata[:chunk_count] = total_chunks

      records << {
        task_id: @task&.id,
        project_id: @project&.id,
        collection: @collection,
        content_type: content_type,
        content: chunk,
        source_url: source_url,
        source_title: source_title,
        metadata: chunk_metadata,
        embedding: embedding,
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    # Perform bulk insert
    if records.any?
      begin
        VectorEmbedding.insert_all!(records)
        # Get the actual records for return value
        VectorEmbedding.where(collection: @collection, content: pending_chunks)
      rescue => e
        Rails.logger.error("Database commit failed: #{e.message}")
        []
      end
    else
      []
    end
  end

  # Prepare base metadata for embeddings
  def prepare_base_metadata(original_text, chunk_size, chunk_overlap, content_type, source_url, source_title, metadata)
    full_metadata = {
      content_type: content_type,
      source_url: source_url,
      source_title: source_title,
      embedding_model: EMBEDDING_MODEL,
      timestamp: Time.now.iso8601,
      chunk_size: chunk_size,
      chunk_overlap: chunk_overlap,
      document_size: original_text.bytesize
    }

    # Add task and project info
    full_metadata[:task_id] = @task.id if @task
    full_metadata[:project_id] = @project.id if @project

    # Preserve file path information from metadata
    if metadata.present?
      %i[file_path file_name file_ext file_dir].each do |key|
        full_metadata[key] = metadata[key] if metadata[key].present?
      end

      # Merge remaining metadata
      full_metadata.merge!(metadata)
    end

    full_metadata
  end

  # Returns the embedding vector; raises if unsuccessful
  def generate_huggingface_embedding(text)
    api_key = ENV["HUGGINGFACE_API_TOKEN"]
    raise "HUGGINGFACE_API_TOKEN environment variable not set" unless api_key

    endpoint = ENV["HUGGINGFACE_EMBEDDING_ENDPOINT"] || DEFAULT_API_ENDPOINT
    
    request_body = { inputs: text.to_s, normalize: true }.to_json
    make_api_request(endpoint, api_key, request_body)
  end

  # Make API request with retries
  def make_api_request(endpoint, api_key, request_body)
    require "net/http"
    require "uri"
    require "json"

    uri = URI.parse(endpoint)
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{api_key}"
    request.content_type = "application/json"
    request.body = request_body

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.read_timeout = 180  # 3 minutes
    http.open_timeout = 30
    
    retries = 0
    begin
      response = http.request(request)
      if response.code == "200"
        result = JSON.parse(response.body)

        # Handle different API response formats
        if result.is_a?(Array)
          # Return as is - we'll handle the nested array in the generate_embedding method
          result
        elsif result.is_a?(Hash) && result["embedding"]
          result["embedding"]
        else
          Rails.logger.error("Unexpected embedding format: #{result.class}")
          raise "Unexpected embedding format from API"
        end
      else
        raise "Hugging Face API error: #{response.code} - #{response.body}"
      end
    rescue => e
      retries += 1
      if retries < MAX_RETRIES
        sleep(retries * 10) # Exponential backoff
        retry
      else
        Rails.logger.error("Failed HF embed: #{e.message}")
        raise
      end
    end
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

  # Store content with its embedding in the database
  def store(content:, content_type: "text", source_url: nil, source_title: nil, metadata: {})
    return if content.blank?

    # Prepare metadata
    full_metadata = prepare_metadata(content_type, source_url, source_title, metadata)

    # Generate embedding
    start_time = Time.now
    embedding = generate_embedding(content).flatten
    generation_time = Time.now - start_time

    if embedding.nil? || embedding.empty?
      Rails.logger.error("Embedding generation failed for content: #{content.truncate(100)}")
      raise "Embedding generation failed"
    end

    Rails.logger.info("Generated embedding in #{generation_time.round(2)}s (#{embedding.size} dimensions)")

    # Create record
    VectorEmbedding.create!(
      task_id: @task&.id,
      project_id: @project&.id,
      collection: @collection,
      content_type: content_type,
      content: content,
      source_url: source_url,
      source_title: source_title,
      metadata: full_metadata,
      embedding: embedding
    )
  end

  # Prepare metadata for embedding storage
  def prepare_metadata(content_type, source_url, source_title, metadata)
    full_metadata = {
      content_type: content_type,
      source_url: source_url,
      source_title: source_title,
      embedding_model: EMBEDDING_MODEL,
      timestamp: Time.now.iso8601
    }

    # Add task and project info
    full_metadata[:task_id] = @task.id if @task
    full_metadata[:project_id] = @project.id if @project

    # Merge additional metadata, preserving file path information
    if metadata.present?
      # Ensure file path information is preserved
      %i[file_path file_name file_ext file_dir].each do |key|
        full_metadata[key] = metadata[key] if metadata[key].present?
      end

      # Merge the rest
      full_metadata.merge!(metadata)
    end

    full_metadata
  end

  # Generate embeddings for a batch of texts
  def generate_tei_embeddings(texts, batch_size: API_BATCH_SIZE)
    return [] if texts.empty?
    
    api_key = ENV["HUGGINGFACE_API_TOKEN"]
    Rails.logger.debug("EmbeddingService: API key present? #{api_key.present?}")
    raise "HUGGINGFACE_API_TOKEN environment variable not set" unless api_key

    endpoint = ENV["HUGGINGFACE_EMBEDDING_ENDPOINT"] || DEFAULT_API_ENDPOINT
    Rails.logger.debug("EmbeddingService: Using embedding endpoint: #{endpoint}")
    
    # Process in smaller batches if needed
    results = []
    texts.each_slice(batch_size) do |batch|
      batch_results = process_embedding_batch(batch, endpoint, api_key)
      results.concat(batch_results)
    end
    
    results
  end

  # Process a batch of texts for embedding
  def process_embedding_batch(batch, endpoint, api_key)
    require "net/http"
    require "uri"
    require "json"

    uri = URI.parse(endpoint)
    Rails.logger.debug("EmbeddingService: Creating HTTP request to #{uri}")
    
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{api_key}"
    request.content_type = "application/json"

    request_body = {
      inputs: batch.map(&:to_s),
      normalize: true
    }
    request.body = request_body.to_json
    
    Rails.logger.debug("EmbeddingService: Payload size: #{request.body.bytesize} bytes, #{batch.size} texts")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.read_timeout = 300  # 5 minutes
    http.open_timeout = 30
    
    Rails.logger.debug("EmbeddingService: Sending embedding request to API")

    retries = 0
    begin
      response = http.request(request)
      
      if response.code == "200"
        Rails.logger.debug("EmbeddingService: Received successful response (#{response.body.bytesize} bytes)")
        batch_results = JSON.parse(response.body)
        
        if batch_results.is_a?(Array) && batch_results.length == batch.size
          Rails.logger.debug("EmbeddingService: Successfully parsed response - received #{batch_results.length} embeddings")
          batch_results
        else
          Rails.logger.error("EmbeddingService: Response format error: expected array of #{batch.size} embeddings, got #{batch_results.class}")
          raise "Invalid response format"
        end
      else
        Rails.logger.error("EmbeddingService: API error: #{response.code} - #{response.body}")
        raise "TEI API error: #{response.code} - #{response.body}"
      end
    rescue => e
      retries += 1
      if retries < MAX_RETRIES
        backoff = 15 * retries
        Rails.logger.warn("EmbeddingService: API call failed, retrying (#{retries}/#{MAX_RETRIES}) after #{backoff}s: #{e.message}")
        sleep(backoff)
        retry
      else
        Rails.logger.error("EmbeddingService: Failed to generate embeddings after #{MAX_RETRIES} retries: #{e.message}\n#{e.backtrace.join("\n")}")
        # Return nil placeholders to maintain array positions
        Array.new(batch.size)
      end
    end
  end

  # Efficiently chunk text using a simpler parallel approach
  def parallel_chunk_text(text, chunk_size, chunk_overlap)
    # For small texts, just return the whole thing or process sequentially
    return [text.strip] if text.length <= chunk_size
    
    # For medium texts, use sequential processing - parallelism overhead isn't worth it
    if text.length < 1_000_000
      Rails.logger.debug("EmbeddingService: Text too small for parallel chunking, using sequential chunking")
      return chunk_text_segment(text, chunk_size, chunk_overlap)
    end
    
    # For larger texts, use a simpler and more efficient parallel approach
    processor_count = [Concurrent.processor_count, 1].max
    Rails.logger.debug("EmbeddingService: Using #{processor_count} threads for parallel chunking")
    
    # Divide text into segments more efficiently
    segments = split_text_into_segments(text, processor_count, chunk_size, chunk_overlap)
    Rails.logger.debug("EmbeddingService: Split text into #{segments.size} segments for processing")
    
    # Use a simple thread pool for processing
    all_chunks = process_segments_with_threads(segments, chunk_size, chunk_overlap)
    
    # Remove duplicates that might have been created in overlap regions
    Rails.logger.debug("EmbeddingService: Parallel chunking completed - generated #{all_chunks.size} chunks")
    all_chunks.uniq
  end
  
  # Split text into segments for parallel processing
  def split_text_into_segments(text, processor_count, chunk_size, chunk_overlap)
    # Calculate optimal segment size based on text length and processor count
    # Aim for segments that are roughly equal in size
    target_segment_count = processor_count * 2  # Create 2x segments as processors for better load balancing
    base_segment_size = text.length / target_segment_count
    
    # Ensure segment size is reasonable (not too small)
    segment_size = [base_segment_size, chunk_size * 10].max
    segment_overlap = chunk_size  # Smaller overlap is sufficient
    
    segments = []
    position = 0
    
    while position < text.length
      end_pos = [position + segment_size, text.length].min
      
      # Find a natural breakpoint if not at the end
      if end_pos < text.length
        # Look for paragraph or line breaks near the end position
        search_window = [500, segment_size / 10].min  # Smaller search window
        search_start = [end_pos - search_window, position].max
        search_text = text[search_start...end_pos]
        
        # Try to find a paragraph or line break
        if search_text.include?("\n\n")
          offset = search_text.rindex("\n\n")
          end_pos = search_start + offset + 2 if offset
        elsif search_text.include?("\n")
          offset = search_text.rindex("\n")
          end_pos = search_start + offset + 1 if offset
        end
      end
      
      # Extract segment
      segment = text[position...end_pos]
      segments << segment if segment.length > 0
      
      # Move position with overlap
      position = [end_pos - segment_overlap, position + 1].max
    end
    
    segments
  end
  
  # Process segments using a simple thread pool
  def process_segments_with_threads(segments, chunk_size, chunk_overlap)
    return [] if segments.empty?
    
    # Use a thread pool with a reasonable size
    pool_size = [Concurrent.processor_count, segments.size].min
    
    # Create a thread pool
    pool = Concurrent::FixedThreadPool.new(pool_size)
    
    # Process segments in parallel
    mutex = Mutex.new
    all_chunks = []
    
    # Create and submit tasks
    segments.each_with_index do |segment, idx|
      pool.post do
        begin
          # Process the segment
          start_time = Time.now
          chunks = chunk_text_segment(segment, chunk_size, chunk_overlap)
          duration = Time.now - start_time
          
          # Thread-safe append to results
          mutex.synchronize do
            all_chunks.concat(chunks)
          end
          
          Rails.logger.debug("EmbeddingService: Thread processed segment #{idx+1}/#{segments.size} in #{duration.round(2)}s - #{chunks.size} chunks")
        rescue => e
          Rails.logger.error("EmbeddingService: Error processing segment #{idx+1}: #{e.message}")
        end
      end
    end
    
    # Wait for all tasks to complete
    pool.shutdown
    pool.wait_for_termination(60)  # 60 second timeout
    
    all_chunks
  end

  # Optimized chunking algorithm for a single text segment
  def chunk_text_segment(text, chunk_size, chunk_overlap)
    # For very small texts, just return the whole thing
    return [text.strip] if text.length <= chunk_size

    chunks = []
    position = 0
    text_length = text.length
    
    # Pre-calculate breakpoint patterns for faster matching
    paragraph_break = "\n\n"
    line_break = "\n"
    sentence_end = ". "
    
    while position < text_length
      # Find end position
      end_pos = [position + chunk_size, text_length].min
      
      # Find a natural breakpoint if not at the end
      if end_pos < text_length
        # Use a more efficient approach to find breakpoints
        # Start with a smaller search window
        search_window = [80, chunk_size / 10].min
        search_start = [end_pos - search_window, position].max
        search_text = text[search_start...end_pos]
        
        # Check for breakpoints in order of preference
        if (pos = search_text.rindex(paragraph_break))
          end_pos = search_start + pos + 2
        elsif (pos = search_text.rindex(line_break))
          end_pos = search_start + pos + 1
        elsif (pos = search_text.rindex(sentence_end))
          end_pos = search_start + pos + 2
        elsif (pos = search_text.rindex(" "))
          end_pos = search_start + pos + 1
        end
      end
      
      # Extract chunk and add if not empty
      chunk = text[position...end_pos].strip
      chunks << chunk if chunk.length > 0
      
      # Move position with overlap, ensuring forward progress
      new_position = end_pos - chunk_overlap
      # Ensure we make progress even with large overlaps
      position = new_position > position ? new_position : position + 1
    end
    
    chunks
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
