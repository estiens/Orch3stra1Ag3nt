# frozen_string_literal: true

# Service for managing vector embeddings and RAG functionality
class EmbeddingService
  attr_reader :collection, :task, :project

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
  # @param text [String] The document text to process
  # @param chunk_size [Integer] Size of each chunk
  # @param chunk_overlap [Integer] Overlap between chunks
  # @param content_type [String] Type of content
  # @param source_url [String] Source URL
  # @param source_title [String] Source title
  # @param metadata [Hash] Additional metadata
  # @param force [Boolean] Whether to force processing even if chunks exist
  # @return [Array<VectorEmbedding>] The created embedding records
  def add_document(text, chunk_size: 512, chunk_overlap: 25, content_type: "document", source_url: nil, source_title: nil, metadata: {}, force: false)
    if text.blank?
      Rails.logger.info("Empty document received - nothing to process")
      return []
    end

    start_time = Time.now
    text_size = text.bytesize
    Rails.logger.tagged("EmbeddingService", "add_document") do
      Rails.logger.info("Starting document processing: #{text_size} bytes, chunk_size=#{chunk_size}, overlap=#{chunk_overlap}")

      # Log file information if available
      if metadata[:file_path].present?
        Rails.logger.info("Processing file: #{metadata[:file_path]}")
      end

      # STAGE 1: Chunking
      chunking_start = Time.now
      Rails.logger.info("Stage 1: Chunking document...")
      chunks = chunk_text(text, chunk_size, chunk_overlap)
      chunking_time = Time.now - chunking_start

      Rails.logger.info("Chunking complete: created #{chunks.size} chunks in #{chunking_time.round(2)}s")

      if chunks.empty?
        Rails.logger.warn("No valid chunks extracted from document")
        return []
      end

      # STAGE 2: Duplicate checking
      dedupe_start = Time.now
      Rails.logger.info("Stage 2: Checking for existing chunks...")

      unless force
        existing_chunks = VectorEmbedding.where(collection: @collection, content: chunks).pluck(:content)
        chunks_to_process = chunks - existing_chunks
        Rails.logger.info("Found #{existing_chunks.size} existing chunks, need to process #{chunks_to_process.size} new chunks")
      else
        chunks_to_process = chunks
        Rails.logger.info("Force mode: processing all #{chunks.size} chunks")
      end

      if chunks_to_process.empty?
        Rails.logger.info("All chunks already exist - nothing to process")
        return []
      end

      # STAGE 3: Embedding generation and periodic database commits
      Rails.logger.info("Stage 3: Processing #{chunks_to_process.size} chunks with periodic database commits")

      # Configuration
      api_batch_size = 8  # Size for API calls
      db_commit_frequency = 10  # Commit to DB every X API batches

      # Prepare for processing
      total_api_batches = (chunks_to_process.size.to_f / api_batch_size).ceil
      all_results = []
      total_saved = 0

      # Buffers for accumulating chunks before DB commit
      pending_chunks = []
      pending_embeddings = []

      # Process in small batches for API calls
      chunks_to_process.each_slice(api_batch_size).with_index do |api_batch, api_batch_idx|
        api_batch_num = api_batch_idx + 1
        batch_start = Time.now

        Rails.logger.info("Processing API batch #{api_batch_num}/#{total_api_batches} (#{api_batch.size} chunks)")

        begin
          # Generate embeddings for this API batch
          batch_embeddings = generate_tei_embeddings(api_batch)

          # Add to pending buffers
          pending_chunks.concat(api_batch)
          pending_embeddings.concat(batch_embeddings)

          # Log API batch completion
          batch_time = Time.now - batch_start
          Rails.logger.info("API batch #{api_batch_num}/#{total_api_batches} complete in #{batch_time.round(2)}s " +
                           "(#{pending_chunks.size} chunks pending DB commit)")

          # If we've reached commit frequency or this is the last batch, commit to database
          if (api_batch_num % db_commit_frequency == 0) || (api_batch_num == total_api_batches)
            db_start = Time.now
            commit_size = pending_chunks.size
            Rails.logger.info("Committing #{commit_size} chunks to database...")

            # Prepare metadata for all records
            base_metadata = {
              content_type: content_type,
              source_url: source_url,
              source_title: source_title,
              embedding_model: "gte-large-buc",
              timestamp: Time.now.iso8601,
              chunk_size: chunk_size,
              chunk_overlap: chunk_overlap,
              document_size: text_size
            }

            # Add task and project info
            base_metadata[:task_id] = @task.id if @task
            base_metadata[:project_id] = @project.id if @project

            # Preserve file path information from metadata
            if metadata.present?
              %i[file_path file_name file_ext file_dir].each do |key|
                base_metadata[key] = metadata[key] if metadata[key].present?
              end

              # Merge remaining metadata
              base_metadata.merge!(metadata)
            end

            # Build records for bulk insert
            records = []
            pending_chunks.zip(pending_embeddings).each_with_index do |(chunk, embedding), chunk_idx|
              next if embedding.nil?

              # Add chunk-specific metadata
              chunk_metadata = base_metadata.dup
              chunk_metadata[:chunk_index] = chunk_idx
              chunk_metadata[:chunk_count] = chunks.size

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
                inserted = VectorEmbedding.insert_all!(records)
                saved_count = inserted.count
                total_saved += saved_count

                # Get the actual records for return value
                new_records = VectorEmbedding.where(collection: @collection, content: pending_chunks)
                all_results.concat(new_records)

                # Log success
                db_time = Time.now - db_start
                Rails.logger.info("Database commit successful: #{saved_count} records saved in #{db_time.round(2)}s " +
                                "(#{total_saved}/#{chunks_to_process.size} total, #{(total_saved.to_f/chunks_to_process.size*100).round}%)")
              rescue => e
                Rails.logger.error("Database commit failed: #{e.message}")
                Rails.logger.error(e.backtrace.join("\n"))
              end
            end

            # Clear buffers after commit
            pending_chunks = []
            pending_embeddings = []
          end

        rescue => e
          Rails.logger.error("Error in API batch #{api_batch_num}: #{e.message}")
          Rails.logger.error(e.backtrace.join("\n"))
          # Continue with next batch
        end
      end

      # Final stats
      total_time = Time.now - start_time
      Rails.logger.info("Document processing complete: #{total_saved}/#{chunks_to_process.size} chunks saved " +
                       "in #{total_time.round(2)}s (#{(total_time/60).round(1)} minutes)")

      all_results
    end
  end


  # Simplified batch embedding method - no progress thread
  def generate_tei_batch(texts)
    return [] if texts.empty?

    require "net/http"
    require "uri"
    require "json"

    api_key = ENV["HUGGINGFACE_API_TOKEN"]
    endpoint = ENV["HUGGINGFACE_EMBEDDING_ENDPOINT"] || "https://piujqyd9p0cdbgx1.us-east4.gcp.endpoints.huggingface.cloud"
    uri = URI.parse(endpoint)

    # Prepare request
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{api_key}"
    request.content_type = "application/json"

    # Prepare payload
    request.body = {
      inputs: texts.map(&:to_s),
      normalize: true
    }.to_json

    # Configure connection
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.read_timeout = 180  # 3 minutes
    http.open_timeout = 30

    # Send request
    Rails.logger.info("Sending embedding request for #{texts.size} texts")
    response = http.request(request)

    if response.code == "200"
      batch_results = JSON.parse(response.body)

      # Verify response structure
      if batch_results.is_a?(Array) && batch_results.length == texts.size
        Rails.logger.info("Successfully received #{batch_results.length} embeddings")
        batch_results
      else
        Rails.logger.error("Response format error: expected array of #{texts.size} embeddings")
        raise "Invalid response format"
      end
    else
      Rails.logger.error("API error: #{response.code} - #{response.body}")
      raise "API error: #{response.code} - #{response.body}"
    end
  end




  # Remove all embeddings in collection (DANGEROUS)
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
    response = llm.chat(messages: [ { role: "user", content: prompt } ])
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
    if embedding.size != 1024
      if embedding.size < 1024
        embedding = embedding + Array.new(1024 - embedding.size, 0.0)
      else
        embedding = embedding[0...1024]
      end
    end

    embedding
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

  # Returns the embedding vector; raises if unsuccessful
  def generate_huggingface_embedding(text)
    require "net/http"
    require "uri"
    require "json"

    api_key = ENV["HUGGINGFACE_API_TOKEN"]
    raise "HUGGINGFACE_API_TOKEN environment variable not set" unless api_key

    endpoint = ENV["HUGGINGFACE_EMBEDDING_ENDPOINT"] || "https://piujqyd9p0cdbgx1.us-east4.gcp.endpoints.huggingface.cloud"
    uri = URI.parse(endpoint)
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{api_key}"
    request.content_type = "application/json"
    request.body = { inputs: text.to_s, normalize: true }.to_json

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    retries = 0

    begin
      response = http.request(request)
      if response.code == "200"
        # Parse the response body
        result = JSON.parse(response.body)

        # The API can return different formats:
        # 1. An array of embeddings: [[float, float, ...]]
        # 2. A single embedding: [float, float, ...]
        # 3. An object with an embedding key: {"embedding": [float, float, ...]}

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
      if retries < 3
        sleep(retries * 10) # Exponential backoff
        retry
      else
        Rails.logger.error("Failed HF embed: #{e.message}")
        raise
      end
    end
  end

  # Store content with its embedding in the database
  # @param content [String] The content to store
  # @param content_type [String] The type of content
  # @param source_url [String] Optional source URL
  # @param source_title [String] Optional source title
  # @param metadata [Hash] Additional metadata
  # @return [VectorEmbedding] The created embedding record
  def store(content:, content_type: "text", source_url: nil, source_title: nil, metadata: {})
    return if content.blank?

    # Prepare metadata
    full_metadata = {
      content_type: content_type,
      source_url: source_url,
      source_title: source_title,
      embedding_model: "huggingface",
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


  def generate_tei_embeddings(texts, batch_size: 8)
    require "net/http"
    require "uri"
    require "json"

    api_key = ENV["HUGGINGFACE_API_TOKEN"]
    raise "HUGGINGFACE_API_TOKEN environment variable not set" unless api_key

    endpoint = ENV["HUGGINGFACE_EMBEDDING_ENDPOINT"] || "https://piujqyd9p0cdbgx1.us-east4.gcp.endpoints.huggingface.cloud"
    uri = URI.parse(endpoint)

    Rails.logger.tagged("TEIEmbedding") do
      # Calculate batches
      total_batches = (texts.size.to_f / batch_size).ceil
      Rails.logger.info("Generating embeddings for #{texts.size} texts in #{total_batches} batches")

      results = []
      texts.each_slice(batch_size).with_index do |batch, batch_idx|
        batch_start = Time.now
        Rails.logger.info("Processing batch #{batch_idx+1}/#{total_batches} with #{batch.size} texts")

        # Prepare request
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{api_key}"
        request.content_type = "application/json"

        # Show text sizes for debugging
        text_sizes = batch.map(&:bytesize)
        Rails.logger.debug("Text sizes in batch: min=#{text_sizes.min}, max=#{text_sizes.max}, avg=#{text_sizes.sum / batch.size}")

        # Log sample text for debugging
        Rails.logger.debug("Sample text: #{batch.first.truncate(100)}") if batch.first

        # Prepare payload
        request_body = {
          inputs: batch.map(&:to_s),
          normalize: true
        }

        request.body = request_body.to_json
        request_size = request.body.bytesize
        Rails.logger.info("Request payload size: #{request_size} bytes")

        # Set up connection with appropriate timeouts
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        http.read_timeout = 300  # 5 minutes
        http.open_timeout = 30

        # Track API call time
        api_start = Time.now
        Rails.logger.info("Sending API request to #{endpoint}")

        begin
          response = http.request(request)
          api_time = Time.now - api_start
          Rails.logger.info("Received API response in #{api_time.round(2)}s, status: #{response.code}")

          if response.code == "200"
            batch_results = JSON.parse(response.body)

            # Verify response
            if batch_results.is_a?(Array)
              if batch_results.length == batch.size
                Rails.logger.info("Successfully received #{batch_results.length} embeddings")
                results.concat(batch_results)
              else
                Rails.logger.error("Response count mismatch: expected #{batch.size}, got #{batch_results.length}")
                raise "Embedding count mismatch in response"
              end
            else
              Rails.logger.error("Unexpected response format: #{batch_results.class} instead of Array")
              raise "Invalid response format"
            end
          else
            Rails.logger.error("API error: #{response.code} - #{response.body}")
            raise "TEI API error: #{response.code} - #{response.body}"
          end

          batch_time = Time.now - batch_start
          Rails.logger.info("Batch #{batch_idx+1} completed in #{batch_time.round(2)}s (#{(batch_time/batch.size).round(3)}s per text)")

        rescue => e
          retries ||= 0
          if retries < 3
            retries += 1
            backoff = 15 * retries
            Rails.logger.warn("Embedding failure, retry #{retries}/3 after #{backoff}s delay: #{e.message}")
            sleep(backoff)
            retry
          else
            Rails.logger.error("Failed to generate embeddings after 3 retries: #{e.message}")
            Rails.logger.error(e.backtrace.join("\n"))
            # Return nil placeholders to maintain array positions
            batch.size.times { results << nil }
          end
        end
      end

      Rails.logger.info("Embedding generation complete - #{results.count} total embeddings")
      results
    end
  end



  def chunk_text(text, chunk_size, chunk_overlap)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # For very small texts, just return the whole thing
    if text.length <= chunk_size
      Rails.logger.info("Text smaller than chunk size, returning as single chunk")
      return [ text.strip ]
    end

    # Ultra-fast chunking approach
    chunks = []
    position = 0
    text_length = text.length

    # Use a simple character-based chunking approach for speed
    while position < text_length
      # Find end position (simple math, no searching)
      end_pos = [ position + chunk_size, text_length ].min

      # Only do breakpoint search within a limited window
      if end_pos < text_length
        # Quick search for a good breakpoint - limit search to last 100 chars only
        search_start = [ position + chunk_size - 100, position ].max
        search_text = text[search_start...end_pos]

        # Try to find paragraph break (fastest to slowest)
        break_pos = nil

        # First look for paragraph breaks (fastest checks first)
        if search_text.include?("\n\n")
          offset = search_text.rindex("\n\n")
          break_pos = search_start + offset + 2 if offset
        elsif search_text.include?("\n")
          offset = search_text.rindex("\n")
          break_pos = search_start + offset + 1 if offset
        elsif search_text.include?(". ")
          offset = search_text.rindex(". ")
          break_pos = search_start + offset + 2 if offset
        elsif search_text.include?(" ")
          offset = search_text.rindex(" ")
          break_pos = search_start + offset + 1 if offset
        end

        # If we found a breakpoint, use it
        end_pos = break_pos if break_pos
      end

      # Extract chunk - no additional processing or validation
      chunk = text[position...end_pos].strip
      chunks << chunk if chunk.length > 0

      # Move position with overlap
      position = end_pos - chunk_overlap
      position = position + 1 if position <= end_pos - chunk_size  # Ensure progress
    end

    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
    chunks_per_second = chunks.size / [ duration, 0.001 ].max  # Avoid division by zero

    Rails.logger.info("Fast chunking completed: #{chunks.size} chunks in #{duration.round(3)}s (#{chunks_per_second.round(1)} chunks/sec)")

    chunks
  end



  # Example: supports .txt, .md, .pdf (w/ gem), .docx (w/ gem), .html, etc.
  def parse_file(path)
    ext = File.extname(path).downcase
    case ext
    when ".txt", ".md"
      [ File.read(path), "text" ]
    when ".pdf"
      [ extract_pdf_text(path), "pdf" ]
    when ".docx"
      [ extract_docx_text(path), "docx" ]
    when ".html", ".htm"
      [ extract_html_text(path), "html" ]
    else
      [ File.read(path), "unknown" ]
    end
  rescue => e
    Rails.logger.error("Error parsing #{path}: #{e.message}")
    [ "Error parsing file: #{e.message}", "error" ]
  end

  def extract_pdf_text(path)
    # Placeholder; use PDF parsing gem in production
    "PDF text extraction would happen here for: #{path}"
  end

  def extract_docx_text(path)
    # Placeholder; use DOCX parsing gem in production
    "DOCX text extraction would happen here for: #{path}"
  end

  def extract_html_text(path)
    require "nokogiri"
    html = Nokogiri::HTML(File.read(path))
    html.css("script, style").remove
    html.text.strip
  end

  def llm
    Langchain::LLM::OpenRouter.new(
      api_key: ENV["OPEN_ROUTER_API_KEY"],
      default_options: {
        chat_model: Rails.configuration.llm[:models][:fast],
        temperature: 0.2
      }
    )
  end
end
